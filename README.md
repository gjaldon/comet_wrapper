# CometWrapper

A wrapped token for any of the Compound III tokens.

## Deployments

| Network  | Base Asset | CometWrapper Address                       |
| -------- | ---------- | ------------------------------------------ |
| Mainnet  | USDC       | [0xFd55fCd10d7De6C6205dBBa45C4aA67d547AD8F2](https://etherscan.io/address/0xFd55fCd10d7De6C6205dBBa45C4aA67d547AD8F2) |
| Mainnet  | WETH       | [0x10c739DfABfe1230ca1193de1D6c95230377AdB7](https://etherscan.io/address/0x10c739dfabfe1230ca1193de1d6c95230377adb7) |
| Polygon  | USDC       | Upcoming                                   |
| Arbitrum | USDC       | Upcoming                                   |
| Avalance | USDC       | Upcoming                                   |
| Base     | USDC       | Upcoming                                   |
| Base     | WETH       | Upcoming                                   |

## Overview

Compound III tokens like cUSDCv3 and cWETHv3 are rebasing tokens. Protocols are designed to work with tokens that do not automatically increase balances like rebasing tokens do. The standard solution to this problem is to use a wrapped token.
This wrapped token allows other protocols to more easily integrate with Compound III tokens and treat it like any standard ERC20 token.

## Design Decisions

`CometWrapper` was designed to nullify inflation attacks which could cause losses for users. It's a method of manipulating the price of Wrapped tokens which enables attackers to steal underlying tokens from target depositors or make it prohibitively expensive for future depositors to use the contract.

To nullify inflation attacks, `CometWrapper` maintains internal accounting of all Compound III tokens deposited and withdrawn. This internal accounting only gets updated through the functions `mint`, `redeem`, `deposit` and `withdraw`. This means that any direct transfer of Compound III tokens will not be recognized by the `CometWrapper` contract to prevent malicious actors from manipulating the exchange rate of Wrapped Compound III token to the actual Compound III token. The tradeoff is that any tokens directly transferred to `CometWrapper` will be forever locked and unrecoverable.

### Shares Redemption

When doing Comet transfers, Comet may decrease sender's principal by 1 more than the specified amount in favor of the receiver. To take into account this quirk of Comet transfers, this CometWrapper will always transfer assets worth `shares - 1` and burn `shares` amount when calling `redeem`. 

In this way, any rounding error would be in favor of CometWrapper and at the expense of users. The loss for users is negligible since it is only 1 unit of Wrapped cUSDCv3. However, this serves as protection against insolvency for CometWrapper so that it nevers ends up in a state where users' total shares is greater than the total supply of Wrapped cUSDCv3. Note that the loss of 1 share does not always happen for every redeem and in some cases the decrease in shares for the user and the contract is equal. 

### Non-standard ERC-4626 Behavior

`mint` and `redeem` will not result in exactly `shares` amount of shares minted or redeemed, which is the standard behavior for ERC-4626. This is because CometWrapper uses `userBasic.principal` in Comet to represent `shares` and they map 1:1. Since principal in Comet may round up during transfers or round down during Comet.deposit() or Comet.withdraw(), shares minted or redeemed will have the same behavior. This tradeoff is done so we may maintain the invariant that `totalSupply` of shares in CometWrapper is always equal to the CometWrapper's `userBasic.principal` in Comet.

## Usage

`CometWrapper` implements the ERC4626 Tokenized Vault Standard and is used like any other ERC4626 contracts.

### Wrapping Tokens

To wrap a Compound III token like cUSDCv3, you will need to have cUSDCv3 balance in your wallet and then do the following:

1. `comet.allow(cometWrapperAddress, true)` - allow CometWrapper to move your cUSDCv3 tokens from your wallet to the CometWrapper contract when you call `deposit` or `mint`.
2. `cometWrapper.mint(amount, receiver)` - the first parameter is the amount of Wrapped tokens to be minted.
   OR `cometWrapper.deposit(amount, receiver)` - the first parameter is the amount of Comet tokens that will be deposited.

### Withdrawing Tokens

To withdraw a Compound III token like cUSDCv3, you may use either `withdraw` or `redeem`. For example:

- `cometWrapper.withdraw(amount, receiver, owner)` - `amount` is the number of Compound III tokens to be withdrawn. You can only withdraw tokens that you deposited.
- `cometWrapper.redeem(amount, receiver, owner)` - `amount` is the number of Wrapped Compound III tokens to be redeemed in exchange for the deposited Compound III tokens.

### Claiming Rewards

Comet tokens deposited in CometWrapper will continue to accrue rewards if reward accrual is enabled in Comet. CometWrapper keeps track of users' rewards and users would earn rewards as they would in Comet. The only difference is in claiming of the rewards. Instead of claiming rewards from the CometRewards contract, users will claim it from CometWrapper like so `cometWrapper.claimTo(alice)`.
