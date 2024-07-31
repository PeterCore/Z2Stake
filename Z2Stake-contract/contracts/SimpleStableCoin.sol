// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
// 在这之前我们已经了解过“清算机制”。现在让我们来想一想清算机制该如何实现吧。
//首先，我们刚刚提到了清算阈值，为了计算这个阈值，我们需要定义一个清算率，这个清算率会代表当抵押物的价值下降到贷款数额的百分之多少时会触发清算。
//举个例子，当你以1个 ETH（100美元）作为抵押物，抵押率为150％时，你会获得66个稳定币作为贷款，你的贷款额就为66美元。
//而这时我们定义清算率为80％，当 ETH 的价格跌落到82及美元以下时，就会触发清算。
//这是因为，抵押物价值乘以清算率82*0.8=65.6，已经低于了你的贷款数额。在触发清算后，你的抵押物余额和总额将被清零。
//而相应的，清算者会获得你抵押物的一部分作为回报，这个回报率在每个项目中都不相同，在接下来的示例代码中，我们将清算回报率定为80％
// step1：进入 remix，部署 MockToken 合约。
// step2：将 MockToken 合约的地址作为 SimpleStableCoin 构造函数的第一个参数，第二个参数质押率为150，第三个参数清算率为80，部署 SimpleStableCoin 合约.
// step3：打开 MockToken 合约的下拉框，将 SimpleStableCoin 合约地址复制到MockToken的approve函数第一个参数的位置，授权大于1个代币。
// step4：收起 MockToken 合约，打开 SimpleStableCoin 合约下拉框，找到 depositCollateral 函数，输入1点击调用。存入质押物
// step5：调用 setPrice 函数，将价格设置为99。
// 这一步需要在换取稳定币之前完成
// step6：随后找到 mintStableCoin 函数，输入1点击调用。换取稳定币
// step7：查询当前用户状态，包括稳定币余额，抵押物余额等信息。
//step8：调用 setPrice ，将价格设置为83，模拟市场价格波动。
//step9：尝试清算用户。
// 这是由于在当前参数的情况下，通过计算得到清算价格应该在82
// step10：调用 setPrice ，将价格设置为小于等于82。step11：尝试清算用户。
// 这时就会清算成功了
// step12：查询当前用户状态，包括稳定币余额，抵押物余额等信息。
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleStableCoin is ERC20 {
    IERC20 public collateralToken;
    mapping(address => uint256) public totalCollateral;
    mapping(address => uint256) public remainingCollateral;
    mapping(address => uint256) private loanAmount;
    uint256 public collateralRatio;
    uint256 public liquidationRatio;
    uint256 public price;

    constructor(
        address _collateralToken,
        uint256 _collateralRatio,
        uint256 _liquidationRatio
    ) ERC20("SimpleStableCoin", "SSC") {
        collateralToken = IERC20(_collateralToken);
        collateralRatio = _collateralRatio;//质押率
        liquidationRatio = _liquidationRatio;//清算率
    }

    function setPrice(uint256 _price) public {
        price = _price;
    }

    function depositCollateral(uint256 collateralAmount) external {
        collateralToken.transferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );
        remainingCollateral[msg.sender] += collateralAmount;
        totalCollateral[msg.sender] += collateralAmount;
    }

    function withdrawCollateral(uint256 collateralAmount) external {
        require(
            remainingCollateral[msg.sender] >= collateralAmount,
            "Not enough collateral deposited"
        );
        collateralToken.transfer(msg.sender, collateralAmount);
        remainingCollateral[msg.sender] -= collateralAmount;
        totalCollateral[msg.sender] -= collateralAmount;
    }

    //mintStableCoin 函数，输入1点击调用。换取稳定币
    function mintStableCoin(uint256 collateralAmount) external {
        require(
            remainingCollateral[msg.sender] >= collateralAmount,
            "Not enough collateral deposited"
        );
        uint256 rewardStable = (collateralAmount * price * 100) /
            collateralRatio;
        remainingCollateral[msg.sender] -= collateralAmount;
        loanAmount[msg.sender] += rewardStable;
        _mint(msg.sender, rewardStable);
    }

    function burnStableCoin(uint256 stableCoinAmount) external {
        require(
            loanAmount[msg.sender] >= stableCoinAmount,
            "incorrect parameter"
        );
        uint256 returnedCollateral = stableCoinAmount * collateralRatio / 100 / price;
        remainingCollateral[msg.sender] += returnedCollateral;
        loanAmount[msg.sender] -= stableCoinAmount;
        _burn(msg.sender, stableCoinAmount);
    }

    function liquidate(address user) external {
        uint256 collateralValue = totalCollateral[user] * price;

        require(
            collateralValue * liquidationRatio / 100 < loanAmount[user],
            "User is not undercollateralized"
        );
        uint256 liquidatedCollateral = totalCollateral[user];
        totalCollateral[user] = 0;

        remainingCollateral[user] = 0;
        collateralToken.transfer(msg.sender, liquidatedCollateral);
    }
}

contract MockToken is ERC20 {
    constructor() ERC20("HackQuest", "HQ") {
        _mint(msg.sender, 10 * 10**18);
    }
}