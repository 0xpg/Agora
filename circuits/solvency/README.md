# Solvency eligibility circuit

Proves possession of a deposited amount at or above a threshold, without
revealing the deposit's secret, amount, or position in the pool's Merkle
tree. Public inputs: `pool_root`, `trader`, `epoch`, `threshold_value`.
Public output: a nullifier scoped to `(secret, epoch)`.

Hashing is keccak256 throughout (leaf commitment, Merkle combine, nullifier),
each digest reduced mod the BN254 scalar field, so it matches
`SolvencyMerkleTree.sol`'s on-chain tree exactly rather than needing a
Grumpkin/Pedersen implementation in Solidity. Vendored locally in `src/keccak.nr`
(single-block only — every call site here is well under the 136-byte rate)
rather than pulled in as an external dependency.

## Build & test

```shell
nargo test
```

## Regenerating the on-chain verifier

```shell
nargo compile
bb write_vk -s ultra_honk --oracle_hash keccak -b target/solvency.json -o target
bb write_solidity_verifier -s ultra_honk -k target/vk -o target/Verifier.sol
cp target/Verifier.sol ../../src/SolvencyVerifier.sol
```

`--oracle_hash keccak` is required — it's what makes the proof's Fiat-Shamir
transcript cheap to reproduce on-chain via the EVM's native opcode instead of
a circuit-native hash.

## Regenerating the test fixture

`test/fixtures/solvency/{proof,public_inputs}.hex` in the main Foundry project
back `test/SolvencyVerifierIntegration.t.sol`, which deposits the same leaf
on-chain and checks the resulting root matches what this proof was built
against — so the fixture and `Prover.toml` must stay a matched pair.

```shell
nargo execute solvency_witness
bb prove -s ultra_honk --oracle_hash keccak -b target/solvency.json -w target/solvency_witness.gz -o target
python3 -c "
with open('target/proof','rb') as f: proof = f.read()
with open('target/public_inputs','rb') as f: pubs = f.read()
open('target/proof.hex','w').write('0x' + proof.hex())
with open('target/public_inputs.hex','w') as f:
    for i in range(len(pubs)//32):
        f.write('0x' + pubs[i*32:(i+1)*32].hex() + '\n')
"
cp target/proof.hex target/public_inputs.hex ../../test/fixtures/solvency/
```
