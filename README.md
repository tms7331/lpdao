# LPDAO - Hedge Fund in a Hook

### Overview

LPDAO allows LPs to pool their funds and elect a fund manager to manage their funds in a trustless manner.  The fund manager only gets paid if they actually return a profit, so incentives are aligned.

### Solution

By utilizing an upgradeable proxy contract to control fees and access to swapping and liquidity provisioning, this system introduces flexibility and trust. LPs can elect a fund manager with specific permissions to manage liquidity pools while ensuring that the manager cannot access user funds directly. The system is designed to be upgradeable, allowing future improvements without disrupting the overall functionality.

### Key Features

1. **Fund Manager Incentives**: The manager is only paid if they generate a profit for the liquidity pool, aligning their incentives with LPs.
2. **Upgradeable Contracts**: The proxy contract allows the system to be updated and extended with new features, enabling long-term flexibility.
3. **Intermediate Trust**: While the fund manager is given permission to perform actions such as adjusting swap fees or disabling pools, they are never able to access user funds directly, maintaining a secure environment.
4. **Voting System**: LPs can propose and vote on changes to the system, such as electing a new fund manager or upgrading the proxy contract, making the system decentralized and community-driven.

### Contracts

- **LPDao.sol** - The core contract that manages the liquidity pool and hooks.
- **Voting.sol** - A voting system that is integrated into the hooks, allowing LPs to propose and vote on changes.
- **HookExtensionProxy.sol** - An upgradeable proxy contract that controls the contract upgrades. Only after a successful vote can the hook, which acts as the admin, approve an upgrade.
- **OnOffExtension.sol** - An example extension that allows a fund manager to enable or disable a pool.
- **AuctionExtension.sol** - Another example extension where an auction is run for the first swap in a block.

### Contract Hooks

The hook inherits from the voting contract and contains two key addresses:
- **Proxy Address (TransparentUpgradeableProxy)**: Controls the system upgrades and is triggered during swaps and liquidity additions.
- **Fund Manager Address**: The elected manager responsible for proposing system upgrades.

The proxy is called in two scenarios:
- **Before Swap**: This function checks whether the swap should proceed, whether the swap fee should be dynamically modified, and returns the fee if applicable.
- **Before Add Liquidity**: Checks whether the liquidity addition should proceed.

### Roles and Governance

- **Fund Manager**: Can propose proxy upgrades and manage certain pool parameters.
- **Liquidity Providers (LPs)**: Can propose new fund managers, vote on proxy upgrades, and vote on changes to the fund manager.

Once a proposal is made, there is a one-week voting period followed by an additional week for changes to take effect. This gives LPs time to withdraw their funds if they disagree with any proposed changes.

## Running Code
*Ensure that you have correctly installed Foundry (Forge) and that it's up to date. You can update Foundry by running:*

```
foundryup
```

## Set up

*requires [foundry](https://book.getfoundry.sh)*

```
forge install
forge test
```
