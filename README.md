# CometWrapper

A wrapped token for any of the Compound III tokens.

## Overview

Compound III tokens like cUSDCv3 and cWETHv3 are rebasing tokens. Protocols are designed to work with tokens that do not automatically increase balances like rebasing tokens do. The standard solution to this problem is to use a wrapped token.
This wrapped token allows other protocols to more easily integrate with Compound III tokens and treat it like any standard ERC20 token.

## Design Decisions

`CometWrapper` was designed to nullify inflation attacks which could cause losses for users. It's a method of manipulating the price of Wrapped tokens which enables attackers to steal underlying tokens from target depositors or make it prohibitively expensive for future depositors to use the contract.

To nullify inflation attacks, `CometWrapper` maintains internal accounting of all Compound III tokens deposited and withdrawn. This internal accounting only gets updated through the functions `mint`, `redeem`, `deposit` and `withdraw`. This means that any direct transfer of Compound III tokens will not be recognized by the `CometWrapper` contract to prevent malicious actors from manipulating the exchange rate of Wrapped Compound III token to the actual Compound III token. The tradeoff is that any tokens directly transferred to `CometWrapper` will be forever locked and unrecoverable.

### Shares Redemption

When doing Comet transfers, Comet may decrease sender's principal by 1 more than the specified amount in favor of the receiver. To take into account this quirk of Comet transfers, this CometWrapper will always transfer assets worth `shares - 1` and burn `shares` amount when calling `redeem`. 

In this way, any rounding error would be in favor of CometWrapper and at the expense of users. The loss for users is negligible since it is only 1 unit of Wrapped cUSDCv3. However, this serves as protection against insolvency for CometWrapper so that it nevers ends up in a state where users' total shares is greater than the total supply of Wrapped cUSDCv3. Note that the loss of 1 share does not always happen for every redeem and in some cases the decrease in shares for the user and the contract is equal. 

## Usage

`CometWrapper` implements the ERC4626 Tokenized Vault Standard and is used like any other ERC4626 contracts.

### Wrapping Tokens

To wrap a Compound III token like cUSDCv3, you will need to have cUSDCv3 balance in your wallet and then do the following:

1. `comet.allow(cometWrapperAddress, true)` - allow CometWrapper to move your cUSDCv3 tokens from your wallet to the CometWrapper contract when you call `deposit` or `mint`.
2. `cometWrapper.mint(amount, receiver)` - the first parameter is the amount of Wrapped tokens to be minted.
   OR `cometWrapper.deposit(amount, receiver)` - the first parameter is the amount of Comet tokens that will be deposited.

### Withdrawing Tokens

To witdhraw a Compound III token like cUSDCv3, you may use either `withdraw` or `redeem`. For example:

- `cometWrapper.withdraw(amount, receiver, owner)` - `amount` is the number of Compound III tokens to be withdrawn. You can only withdraw tokens that you deposited.
- `cometWrapper.redeem(amount, receiver, owner)` - `amount` is the number of Wrapped Compound III tokens to be redeemed in exchange for the deposited Compound III tokens.
