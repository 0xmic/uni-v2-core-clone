# Uniswap V2 Core

This repo is a lightweight clone of the Uniswap V2 Core contracts.  

https://github.com/Uniswap/v2-core/tree/master/contracts

Changes include the following:

- [ ] Use solidity 0.8.0 or higher, don’t use SafeMath
- [ ] Use an existing fixed point library, but not the Uniswap one.
- [ ] Use Openzeppelin’s or Solmate’s safeTransfer instead of building it from scratch like Unisawp does
- [ ] Instead of implementing a flash swap the way Uniswap does, use EIP 3156.