// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LiquidityPool is ERC20 {
    address public tokenA;
    address public tokenB;

    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public totalLiquidity;

    constructor(address _tokenA, address _tokenB) ERC20("HackQuest", "HQ") {
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function addLiquidity(
        uint256 _amountADesierd,
        uint256 _amountBDesierd
    ) external {
        if (reserveA == 0 && reserveB == 0) {
            _addLiquidity(_amountADesierd, _amountBDesierd);
        } else {
            uint256 amountBOptimal = _calculateAmountB_add(_amountADesierd);
            if (amountBOptimal <= _amountBDesierd) {
                //此时注入的流动性为_amountADesierd和amountBOptimal
                _addLiquidity(_amountADesierd, amountBOptimal);
            } else {
                uint256 amountAOptimal = _calculateAmountA_add(_amountBDesierd);
                //此时注入的流动性为amountAOptimal和_amountBDesierd
                _addLiquidity(amountAOptimal, _amountBDesierd);
            }
        }
    }

    function _calculateAmountB_add(
        uint256 _amountADesierd
    ) internal view returns (uint256) {
        return (reserveB * _amountADesierd) / reserveA;
    }

    function _calculateAmountA_add(
        uint256 _amountBDesierd
    ) internal view returns (uint256) {
        return (reserveA * _amountBDesierd) / reserveB;
    }

    function _addLiquidity(uint256 amountA, uint256 amountB) private {
        uint256 liquidityTokens = calculateLiquidityTokens(amountA, amountB);
        _mint(msg.sender, liquidityTokens);
        reserveA += amountA;
        reserveB += amountB;
        totalLiquidity += liquidityTokens;

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
    }

    function calculateLiquidityTokens(
        uint256 amountA,
        uint256 amountB
    ) private view returns (uint256 liquidityTokens) {
        if (reserveA == 0 && reserveB == 0) {
            liquidityTokens = sqrt(amountA * amountB);
        } else if (reserveA > 0 && reserveB > 0) {
            uint256 liquidityPercentageA = (amountA * totalLiquidity) /
                reserveA;
            uint256 liquidityPercentageB = (amountB * totalLiquidity) /
                reserveB;

            liquidityTokens = (liquidityPercentageA < liquidityPercentageB)
                ? liquidityPercentageA
                : liquidityPercentageB;
        } else {
            revert("Invalid reserve amounts");
        }

        return liquidityTokens;
    }

    function removeLiquidity(uint256 liquidityTokens) external {
        require(
            balanceOf(msg.sender) >= liquidityTokens,
            "liquidity not enough"
        );
        require(totalLiquidity >= liquidityTokens, "Insufficient liquidity");
        _burn(msg.sender, liquidityTokens);
        uint256 amountA = (liquidityTokens * reserveA) / totalLiquidity;
        uint256 amountB = (liquidityTokens * reserveB) / totalLiquidity;

        require(
            IERC20(tokenA).transfer(msg.sender, amountA),
            "Transfer of token A failed"
        );
        require(
            IERC20(tokenB).transfer(msg.sender, amountB),
            "Transfer of token B failed"
        );
        reserveA -= amountA;
        reserveB -= amountB;
        totalLiquidity -= liquidityTokens;
    }

    function swapFromAToB(uint256 amountA) external {
        require(IERC20(tokenA).balanceOf(msg.sender) >= amountA);
        uint256 amountB = calculateAmountB_swap(amountA);
        require(reserveB >= amountB, "tokenB not enough");
        reserveA += amountA;
        reserveB -= amountB;

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transfer(msg.sender, amountB);
    }

    function swapFromBToA(uint256 amountB) external {
        require(IERC20(tokenB).balanceOf(msg.sender) >= amountB);
        uint256 amountA = calculateAmountA_swap(amountB);
        require(reserveA >= amountA, "tokenA not enough");
        reserveB += amountB;
        reserveA -= amountA;

        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        IERC20(tokenA).transfer(msg.sender, amountA);
    }
    //恒定乘积模型中，代币的数量乘积 k 是永远保持不变的。
    //因此，我们可以利用 k 除以 A 的储备量，再加上参与交换的代币 A 的数量，来计算交换后 B 代币的总数量。
    //【公式】k = reverseA * reverseB交换后 B 的总量 = k / (reverseA + amountA)
    function calculateAmountA_swap(
        uint256 amountB
    ) public view returns (uint256) {
        require(amountB > 0, "invalid input");
        uint256 totalAmountA = (reserveA * reserveB) / (reserveB + amountB);
        return reserveA - totalAmountA;
    }

    function calculateAmountB_swap(
        uint256 amountA
    ) public view returns (uint256) {
        require(amountA > 0, "invalid input");
        uint256 totalAmountB = (reserveA * reserveB) / (reserveA + amountA);

        return reserveB - totalAmountB;
    }

    function sqrt(uint256 x) private pure returns (uint256 y) {
        // Calculate the square root of a number (rounded down)
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}

// 定义代币A和代币B

contract MockTokenA is ERC20 {
    constructor() ERC20("TokenA", "HQA") {
        _mint(msg.sender, 10 * 10 ** 18);
    }
}

contract MockTokenB is ERC20 {
    constructor() ERC20("TokenB", "HQB") {
        _mint(msg.sender, 10 * 10 ** 18);
    }
}