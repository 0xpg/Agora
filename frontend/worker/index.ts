import { createPublicClient, http, parseAbiItem, type Address } from 'viem'
import { baseSepolia } from 'viem/chains'
import markets from '../../config/markets.json' with { type: 'json' }

const market = markets['84532'][0]
const START_BLOCK = BigInt(market.deploymentBlock)
const BLOCK_BATCH = 1_000n
const confirmations = 2n

const riskEvent = parseAbiItem(
  'event SwapRiskEvaluated(bool indexed zeroForOne, int256 amountSpecified, uint24 navFee, uint24 inventoryFee, uint24 volatilityFee, uint24 totalFee, uint128 epochGrossFlow, int128 epochNetAssetFlow, uint64 navUpdatedAt)',
)
const flowEvent = parseAbiItem(
  'event FlowRecorded(uint128 assetAmount, int128 netAssetFlow, uint128 grossFlow, uint64 epochStart)',
)
const navEvents = [
  parseAbiItem('event NAVUpdated(uint256 nav, uint64 updatedAt)'),
  parseAbiItem('event NAVScheduled(uint256 nav, uint64 activatesAt)'),
  parseAbiItem('event NAVScheduleCancelled()'),
] as const
const client = createPublicClient({ chain: baseSepolia, transport: http() })

function json(value: unknown, status = 200) {
  return Response.json(value, {
    status,
    headers: {
      'access-control-allow-origin': 'https://agora-3z7.pages.dev',
      'cache-control': status === 200 ? 'public, max-age=10' : 'no-store',
    },
  })
}

export function positiveLimit(value: string | null, fallback = 50, ceiling = 100) {
  const parsed = Number(value)
  return Number.isInteger(parsed) && parsed > 0 ? Math.min(parsed, ceiling) : fallback
}

async function indexChain(db: D1Database) {
  const cursor = await db
    .prepare("SELECT block_number FROM chain_cursor WHERE stream = 'base-sepolia'")
    .first<{ block_number: number }>()
  const fromBlock = cursor ? BigInt(cursor.block_number + 1) : START_BLOCK
  const head = await client.getBlockNumber()
  if (head <= confirmations || fromBlock > head - confirmations) return
  const toBlock = fromBlock + BLOCK_BATCH - 1n < head - confirmations ? fromBlock + BLOCK_BATCH - 1n : head - confirmations

  const [riskLogs, flowLogs, oracleLogs] = await Promise.all([
    client.getLogs({ address: market.hook as Address, event: riskEvent, fromBlock, toBlock, strict: true }),
    client.getLogs({ address: market.hook as Address, event: flowEvent, fromBlock, toBlock, strict: true }),
    client.getLogs({ address: market.navOracle as Address, events: navEvents, fromBlock, toBlock, strict: true }),
  ])

  const txHashes = [...new Set(riskLogs.map((log) => log.transactionHash))]
  const blockNumbers = [...new Set([...riskLogs, ...oracleLogs].map((log) => log.blockNumber))]
  const [transactions, blocks] = await Promise.all([
    Promise.all(txHashes.map((hash) => client.getTransaction({ hash }))),
    Promise.all(blockNumbers.map((blockNumber) => client.getBlock({ blockNumber }))),
  ])
  const senders = new Map(transactions.map((tx) => [tx.hash, tx.from.toLowerCase()]))
  const timestamps = new Map(blocks.map((block) => [block.number, Number(block.timestamp)]))
  const statements: D1PreparedStatement[] = []

  for (const log of riskLogs) {
    const a = log.args
    statements.push(
      db
        .prepare(
          `INSERT OR IGNORE INTO trades
           (event_id, transaction_hash, log_index, block_number, block_timestamp, wallet, zero_for_one,
            amount_specified, nav_fee, inventory_fee, volatility_fee, total_fee, epoch_gross_flow,
            epoch_net_asset_flow, nav_updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        )
        .bind(
          `${log.transactionHash}-${log.logIndex}`,
          log.transactionHash,
          log.logIndex,
          Number(log.blockNumber),
          timestamps.get(log.blockNumber) ?? 0,
          senders.get(log.transactionHash) ?? '0x0000000000000000000000000000000000000000',
          a.zeroForOne ? 1 : 0,
          a.amountSpecified.toString(),
          a.navFee,
          a.inventoryFee,
          a.volatilityFee,
          a.totalFee,
          a.epochGrossFlow.toString(),
          a.epochNetAssetFlow.toString(),
          Number(a.navUpdatedAt),
        ),
    )
  }

  for (const log of flowLogs) {
    statements.push(
      db
        .prepare(
          `UPDATE trades SET asset_amount = ?, epoch_start = ?
           WHERE transaction_hash = ? AND asset_amount IS NULL`,
        )
        .bind(log.args.assetAmount.toString(), Number(log.args.epochStart), log.transactionHash),
    )
  }

  for (const log of oracleLogs) {
    const nav = 'nav' in log.args ? log.args.nav.toString() : null
    const effectiveAt =
      'updatedAt' in log.args
        ? Number(log.args.updatedAt)
        : 'activatesAt' in log.args
          ? Number(log.args.activatesAt)
          : null
    statements.push(
      db
        .prepare(
          `INSERT OR IGNORE INTO nav_events
           (event_id, transaction_hash, block_number, block_timestamp, kind, nav, effective_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
        )
        .bind(
          `${log.transactionHash}-${log.logIndex}`,
          log.transactionHash,
          Number(log.blockNumber),
          timestamps.get(log.blockNumber) ?? 0,
          log.eventName,
          nav,
          effectiveAt,
        ),
    )
  }

  statements.push(
    db
      .prepare(
        `INSERT INTO chain_cursor (stream, block_number) VALUES ('base-sepolia', ?)
         ON CONFLICT(stream) DO UPDATE SET block_number = excluded.block_number`,
      )
      .bind(Number(toBlock)),
  )
  await db.batch(statements)
}

async function api(request: Request, db: D1Database) {
  const url = new URL(request.url)
  if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405)

  if (url.pathname === '/api/market') {
    const [cursor, latestTrade, latestNav] = await Promise.all([
      db.prepare("SELECT block_number FROM chain_cursor WHERE stream = 'base-sepolia'").first(),
      db.prepare('SELECT * FROM trades ORDER BY block_number DESC, log_index DESC LIMIT 1').first(),
      db.prepare('SELECT * FROM nav_events ORDER BY block_number DESC LIMIT 1').first(),
    ])
    return json({ chainId: 84532, market, cursor, latestTrade, latestNav })
  }

  if (url.pathname === '/api/trades') {
    const limit = positiveLimit(url.searchParams.get('limit'))
    const wallet = url.searchParams.get('wallet')?.toLowerCase()
    if (wallet && !/^0x[0-9a-f]{40}$/.test(wallet)) return json({ error: 'Invalid wallet address' }, 400)
    const query = wallet
      ? db.prepare('SELECT * FROM trades WHERE wallet = ? ORDER BY block_number DESC, log_index DESC LIMIT ?').bind(wallet, limit)
      : db.prepare('SELECT * FROM trades ORDER BY block_number DESC, log_index DESC LIMIT ?').bind(limit)
    return json({ trades: (await query.all()).results })
  }

  const tradeHash = url.pathname.match(/^\/api\/trades\/(0x[0-9a-fA-F]{64})$/)?.[1]
  if (tradeHash) {
    const trades = await db
      .prepare('SELECT * FROM trades WHERE transaction_hash = ? ORDER BY log_index')
      .bind(tradeHash.toLowerCase())
      .all()
    return trades.results.length ? json({ trades: trades.results }) : json({ error: 'Trade not found' }, 404)
  }

  if (url.pathname === '/api/risk') {
    const limit = positiveLimit(url.searchParams.get('limit'))
    return json({ events: (await db.prepare('SELECT * FROM trades ORDER BY block_number DESC, log_index DESC LIMIT ?').bind(limit).all()).results })
  }

  if (url.pathname === '/api/nav') {
    const limit = positiveLimit(url.searchParams.get('limit'))
    return json({ events: (await db.prepare('SELECT * FROM nav_events ORDER BY block_number DESC LIMIT ?').bind(limit).all()).results })
  }

  return json({ error: 'Not found' }, 404)
}

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext) {
    if (new URL(request.url).pathname.startsWith('/api/')) ctx.waitUntil(indexChain(env.DB))
    return api(request, env.DB)
  },
  scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(indexChain(env.DB))
  },
} satisfies ExportedHandler<Env>
