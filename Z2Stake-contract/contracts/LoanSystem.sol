// SPDX-License-Identifier: MIT

// 因此，在本节中，我们将详细介绍 reward 函数的逻辑。
//在开始之前，你需要明白奖励计算的方式：领奖区间 * 一个块的利息。
//领奖区间 = 当前区块数 - 上一次领奖区块；一个块的利息 = 用户存款数 / 每多少个代币能够在一个区块中获得1 ether的利息。
//我们领奖区间的计算是通过当前区块数减去上一次领奖区块来确定的。
//当前区块号可以通过block.number()来获取，而我们还需要定义一个变量来记录上一次领奖区块号。
//由于每个用户都对应着一个领奖区块信息，因此我们需要一个映射类型的变量来表示地址⇒区块号的映射。
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LoanSystem {
  IERC20 public lpToken; //流动性奖励代币
}