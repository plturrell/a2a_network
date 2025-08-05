# A2A Network

Ethereum smart-contract suite for the **Agent-to-Agent (A2A) Network** – a decentralized reputation and task-assignment protocol.

## Quick Start

```bash
# install Foundry (https://book.getfoundry.sh)
foundryup

# install deps
forge install

# run tests
forge test -vv

# generate docs
npm run docs
```

## Project Structure

| Path | Purpose |
|------|---------|
| `src/` | Core Solidity contracts |
| `test/` | Foundry test contracts (unit, integration, invariants) |
| `script/` | Deployment & verification scripts |
| `broadcast/` | Forge broadcast logs |
| `.github/workflows/` | CI pipelines |

Key contracts:
- `Pausable.sol` – emergency-stop pattern.
- `AgentRegistry.sol` – on-chain registry of agents & reputations.

## Development

1. Copy `.env.example` → `.env` and fill RPC creds.
2. Start a local Anvil chain: `anvil --fork-url <rpc> &`.
3. Deploy locally: `forge script script/DeployAndVerify.s.sol:DeployAndVerify --broadcast`.
4. Run invariant tests: `forge test --match-contract AgentRegistryInvariant`.

### Lint & Format
```
# Format Solidity
forge fmt

# Lint Solidity
npm run lint
```

### Coverage
```
forge coverage
```

## Deployment

`DeployAndVerify.s.sol` handles network deploy + Etherscan verification. Set the correct network & private key via env vars before running.

## Security

The contracts implement pause‐ability, invariant testing, and CI linting. Please see `SECURITY.md` for disclosure guidelines.

## License

MIT
