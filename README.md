# Uniswap V2 Core

This repo is a lightweight clone of the Uniswap V2 Core contracts.  

https://github.com/Uniswap/v2-core/tree/master/contracts

Changes include the following:

- [X] Use solidity 0.8.0 or higher, don’t use SafeMath
- [X] Use Openzeppelin’s or Solmate’s safeTransfer instead of building it from scratch like Unisawp does
- [X] Instead of implementing a flash swap the way Uniswap does, use EIP 3156.
- [X] Use an existing fixed point library, but not the Uniswap one.
- [X] Implement last recorded balance of token1 and token2 to calculate the TWAP and prevent oracle manipulation.
- [ ] Update Flash Swap fxn signature to take into account security edge cases
- [ ] Review past audits
  - https://web.archive.org/web/20230629073604/https://rskswap.com/audit.html#org56963b6
  - Can review Solodit and see where people went wrong forking
