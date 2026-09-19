#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
forge build
mkdir -p abi
for name in BatchAuctionMarket PermissionedAssetToken NAVOracle IdentityRegistry MarketFactory; do
  python3 -c "import json,sys; json.dump(json.load(open('out/${name}.sol/${name}.json'))['abi'], open('abi/${name}.json','w'), indent=2)"
done
