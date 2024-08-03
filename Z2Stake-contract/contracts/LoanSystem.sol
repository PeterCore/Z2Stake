// SPDX-License-Identifier: MIT

// 因此，在本节中，我们将详细介绍 reward 函数的逻辑。
//在开始之前，你需要明白奖励计算的方式：领奖区间 * 一个块的利息。
//领奖区间 = 当前区块数 - 上一次领奖区块；一个块的利息 = 用户存款数 / 每多少个代币能够在一个区块中获得1 ether的利息。
//我们领奖区间的计算是通过当前区块数减去上一次领奖区块来确定的。
//当前区块号可以通过block.number()来获取，而我们还需要定义一个变量来记录上一次领奖区块号。
//由于每个用户都对应着一个领奖区块信息，因此我们需要一个映射类型的变量来表示地址⇒区块号的映射。
// 定义了一个变量 lastRewardBlock，用于表示用户上次领奖的时间。
//因此，我们可以通过使用当前区块的编号（block.number）减去 lastRewardBlock，来得到用户尚未领取奖励的区块数。
// 刚刚我们提到，每一笔定期挖矿都对应着一个存折信息。因此，我们需要定义一个数据结构来表示存折这样的信息。在确定数据结构前，我们先来想一想存折中需要存储哪些信息：
// 存款人信息 - 标记存款者
// 存款数额 - 作为存款数额的凭证
// 存款开始时间 - 作为锁定期的计算标识
// 利率 - 作为这笔存款利率的计算标识
//刚刚我们定义好了存折信息 lockedInfo。回顾一下，我们刚刚有一个属性 interestRate 来表示利率。
//而在合约中，其实还需要一个全局的变量来表示利率的值，因此我们在这一步中需要定义一个 uint256 类型的变量来表示定期存款的利率。
//一般来讲，利率都是以百分数计算的，例如在银行你的年利率可能为百分之三，当你到达存款期限后，利率的计算为本金×百分之三。
//但是由于 solidity 不支持浮点数的设计，我们不能直接存储百分之三这个数据。
//最简单的方式是将利率存储为3，最后在利率的计算时，将100除掉即可。
//又由于solidity存在除法截断，也就是向下取整，为了减少计算误差，我们可以将存储利率的变量放大一定的倍数后，再除以100乘上放大的倍数。
//因此，我们在该合约中定义的利率以10的8次方为单位（10的8次方表示利率为百分之百）在变量可见性方面，我们选择使用public，因为利率这个值应该是公开透明的
// 1.
// 存款者地址 - msg.sender
// 2.
// 存折的id - lockedId
// 3.
// 存款数额 - lockedAmount
// 首先，定期存款是以存折的形式来保存信息的，当用户需要取款时，只需要将存折id作为输入来调用取款函数即可。
// 而我们在合约中需要检验该存折的锁定期是否到期，若锁定期未到，则不允许取款。
// 若锁定期已到，我们就会将用户的本金加利息结算给用户。
//就像现实生活中我们定期存款一样有一个事件限制，在系统合约中也是如此，这里我们使用 lockDuration 来模拟定期存款时间。

// 刚刚我们限制了调用者必须为存折的拥有者，但别忘了我们的存折是有锁定期的。只有锁定期结束后，才能将存款提取出来。
// 因此，我们需要锁定到期的时间，而在存折信息 info 当中，我们只有锁定开始的时间。
// 那么我们可以用锁定开始的时间加上我们的锁定期，来计算出锁定到期的时间。
// 然后用锁定到期的时间与当前的时间作比较，如果还没有到期，则不能取款，需要将该交易回滚。
//该变量是一个改变精度的变量，当该变量为10的8次方时，代表利率为100%。那么我们就需要一个常量来表示这个精度，以便于计算时准确的扣除10的8次方这个精度。

// 存款者地址
// 存折的 id
// 本金＋利息的金额

// 你已经完成了流动性挖矿的全部流程，但是你还记得 LoanLibrary 合约吗？
// 我们在之前使用 calculateDepositInterest 这样的计算利息的工具函数以及 deleteLockedInfo 这样的删除数组元素的函数。
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./LoanLibrary.sol";
import "./Treasury.sol";



contract LoanSystem {
    struct lockedInfo {
        address user;
        uint256 lockedAmount;
        uint256 startBlock;
        uint256 interestRate;
    }
    uint256 constant INTEREST_COEFFICIENT = 10**8;
    uint256 public immutable interestLockedRate;
    uint256 public immutable interestUnLockedRate;
    uint256 public immutable lockDuration;

    IERC20 public lpToken;
    Treasury public treasury;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public lastRewardBlock;
    mapping(address => bytes32[]) userLockedIds;

    mapping(bytes32 => lockedInfo) lockedInfos;
    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);

    event DepositWithLock(
        address indexed account,
        bytes32 indexed lockedId,
        uint256 lockedAmount
    );

    event WithdrawLocked(
        address indexed account,
        bytes32 indexed lockedId,
        uint256 totalAmount
    );

    event Reward(address indexed account, uint256 interest);

    constructor(
        address _lpToken,
        uint256 _lockDuration,
        uint256 _lockedRate,
        uint256 _unlockedRate
    ) {
        lpToken = IERC20(_lpToken);
        treasury = new Treasury(_lpToken);
        lockDuration = _lockDuration;

        interestLockedRate = _lockedRate;
        interestUnLockedRate = _unlockedRate;
    }

    function deposit(uint256 amount) external {
        reward(msg.sender);
        lpToken.transferFrom(msg.sender, address(treasury), amount);
        balanceOf[msg.sender] += amount;

        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount);
        reward(msg.sender);
        lastRewardBlock[msg.sender] = block.number;
        balanceOf[msg.sender] -= amount;
        treasury.withdrawTo(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function reward(address account) public returns (uint256 interest) {
        require(msg.sender == account || msg.sender == address(this));
        uint256 balance = balanceOf[account];
        uint256 period = block.number - lastRewardBlock[account];
        interest = LoanLibrary.calculateDepositInterest(
            balance,
            interestUnLockedRate,
            period
        );
        treasury.withdrawTo(account, interest);

        lastRewardBlock[msg.sender] = block.number;
        emit Reward(account, interest);
    }

    function depositWithLock(uint256 lockedAmount)
        external
        returns (bytes32 lockedId)
    {
        lpToken.transferFrom(msg.sender, address(treasury), lockedAmount);
        lockedInfo memory info = lockedInfo(
            msg.sender,
            lockedAmount,
            block.number,
            interestLockedRate
        );
        lockedId = keccak256(abi.encode(msg.sender, block.number));
        lockedInfos[lockedId] = info;
        userLockedIds[msg.sender].push(lockedId);
        emit DepositWithLock(msg.sender, lockedId, lockedAmount);
    }

    function withdrawLocked(bytes32 lockedId) external {
        lockedInfo memory info = lockedInfos[lockedId];
        require(msg.sender == info.user);
        require(block.number >= info.startBlock + lockDuration);
        uint256 totalAmount = LoanLibrary.calculateLockedInterest(
            info.lockedAmount,
            info.interestRate,
            INTEREST_COEFFICIENT
        );
        treasury.withdrawTo(msg.sender, totalAmount);
        deleteLockedInfo(lockedId);
        emit WithdrawLocked(msg.sender, lockedId, totalAmount);
    }

    function deleteLockedInfo(bytes32 lockedId) internal {
        address user = lockedInfos[lockedId].user;

        // 从userLockedIds中删除lockedId
        bytes32[] storage lockedIds = userLockedIds[user];
        for (uint256 i = 0; i < lockedIds.length; i++) {
            if (lockedIds[i] == lockedId) {
                // 将要删除的lockedId与数组最后一个元素交换位置，然后从数组中删除最后一个元素
                lockedIds[i] = lockedIds[lockedIds.length - 1];
                lockedIds.pop();
                break;
            }
        }

        // 从lockedInfos中删除lockedId
        delete lockedInfos[lockedId];
    }

    function getBlockNumber() external view returns (uint256) {
        return block.number;
    }

    function incrementBlockNumber() external {
        //调用一次即可让本地的block.number加一
    }
}