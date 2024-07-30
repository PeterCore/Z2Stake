// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract B2Stake is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;
    using Address for address;
    using Math for uint256;

    // ************************************** INVARIANT **************************************

    bytes32 public constant ADMIN_ROLE = keccak256("admin_role");
    bytes32 public constant UPGRADE_ROLE = keccak256("upgrade_role");

    uint256 public constant BTC_PID = 0;
    
    // ************************************** DATA STRUCTURE **************************************
    /*
    Basically, any point in time, the amount of B2s entitled to a user but is pending to be distributed is:

    pending B2 = (user.stAmount * pool.accB2PerST) - user.finishedB2

    Whenever a user deposits or withdraws staking tokens to a pool. Here's what happens:
    1. The pool's `accB2PerST` (and `lastRewardBlock`) gets updated.
    2. User receives the pending B2 sent to his/her address.
    3. User's `stAmount` gets updated.
    4. User's `finishedB2` gets updated.
    */
    struct Pool {
        // Address of staking token
        address stTokenAddress;
        // Weight of pool
        uint256 poolWeight;
        // Last block number that B2s distribution occurs for pool
        uint256 lastRewardBlock;
        // Accumulated B2s per staking token of pool
        uint256 accB2PerST;
        // Staking token amount
        uint256 stTokenAmount;
        // Min staking amount
        uint256 minDepositAmount;
        // Withdraw locked blocks
        uint256 unstakeLockedBlocks;
    }

    struct UnstakeRequest {
        // Request withdraw amount
        uint256 amount;
        // The blocks when the request withdraw amount can be released
        uint256 unlockBlocks;
    }

    struct User {
        // Staking token amount that user provided
        uint256 stAmount;
        // Finished distributed B2s to user
        uint256 finishedB2;
        // Pending to claim B2s
        uint256 pendingB2;
        // Withdraw request list
        UnstakeRequest[] requests;
    }

    // ************************************** STATE VARIABLES **************************************
    // First block that B2Stake will start from
    uint256 public startBlock;
    // First block that B2Stake will end from
    uint256 public endBlock;
    // B2 token reward per block
    uint256 public b2PerBlock;

    // Pause the withdraw function
    bool public withdrawPaused;
    // Pause the claim function
    bool public claimPaused;

    // B2 token
    IERC20 public B2;

    // Total pool weight / Sum of all pool weights
    uint256 public totalPoolWeight;
    Pool[] public pool;

    // pool id => user address => user info
    mapping (uint256 => mapping (address => User)) public user;

    // ************************************** EVENT **************************************

    event SetB2(IERC20 indexed B2);

    event PauseWithdraw();

    event UnpauseWithdraw();

    event PauseClaim();

    event UnpauseClaim();

    event SetStartBlock(uint256 indexed startBlock);

    event SetEndBlock(uint256 indexed endBlock);

    event SetB2PerBlock(uint256 indexed b2PerBlock);

    event AddPool(address indexed stTokenAddress, uint256 indexed poolWeight, uint256 indexed lastRewardBlock, uint256 minDepositAmount, uint256 unstakeLockedBlocks);

    event UpdatePoolInfo(uint256 indexed poolId, uint256 indexed minDepositAmount, uint256 indexed unstakeLockedBlocks);

    event SetPoolWeight(uint256 indexed poolId, uint256 indexed poolWeight, uint256 totalPoolWeight);

    event UpdatePool(uint256 indexed poolId, uint256 indexed lastRewardBlock, uint256 totalB2);

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);

    event RequestUnstake(address indexed user, uint256 indexed poolId, uint256 amount);

    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount, uint256 indexed blockNumber);

    event Claim(address indexed user, uint256 indexed poolId, uint256 b2Reward);

    // ************************************** MODIFIER **************************************

    modifier checkPid(uint256 _pid) {
        require(_pid < pool.length, "invalid pid");
        _;
    }

    modifier whenNotClaimPaused() {
        require(!claimPaused, "claim is paused");
        _;
    }

    modifier whenNotWithdrawPaused() {
        require(!withdrawPaused, "withdraw is paused");
        _;
    }

    /**
     * @notice Set B2 token address. Set basic info when deploying.
     */
    function initialize(
        IERC20 _B2,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _b2PerBlock
    ) public initializer {
        require(_startBlock <= _endBlock && _b2PerBlock > 0, "invalid parameters");

        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADE_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        setB2(_B2);

        startBlock = _startBlock;
        endBlock = _endBlock;
        b2PerBlock = _b2PerBlock;

    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADE_ROLE)
        override
    {

    }

    // ************************************** ADMIN FUNCTION **************************************

    /**
     * @notice Set B2 token address. Can only be called by admin
     */
    function setB2(IERC20 _B2) public onlyRole(ADMIN_ROLE) {
        B2 = _B2;

        emit SetB2(B2);
    }

    /**
     * @notice Pause withdraw. Can only be called by admin.
     */
    function pauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(!withdrawPaused, "withdraw has been already paused");

        withdrawPaused = true;

        emit PauseWithdraw();
    }

    /**
     * @notice Unpause withdraw. Can only be called by admin.
     */
    function unpauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(withdrawPaused, "withdraw has been already unpaused");

        withdrawPaused = false;

        emit UnpauseWithdraw();
    }

    /**
     * @notice Pause claim. Can only be called by admin.
     */
    function pauseClaim() public onlyRole(ADMIN_ROLE) {
        require(!claimPaused, "claim has been already paused");

        claimPaused = true;

        emit PauseClaim();
    }

    /**
     * @notice Unpause claim. Can only be called by admin.
     */
    function unpauseClaim() public onlyRole(ADMIN_ROLE) {
        require(claimPaused, "claim has been already unpaused");

        claimPaused = false;

        emit UnpauseClaim();
    }

    /**
     * @notice Update staking start block. Can only be called by admin.
     */
    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        require(_startBlock <= endBlock, "start block must be smaller than end block");

        startBlock = _startBlock;

        emit SetStartBlock(_startBlock);
    }

    /**
     * @notice Update staking end block. Can only be called by admin.
     */
    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE) {
        require(startBlock <= _endBlock, "start block must be smaller than end block");

        endBlock = _endBlock;

        emit SetEndBlock(_endBlock);
    }

    /**
     * @notice Update the B2 reward amount per block. Can only be called by admin.
     */
    function setB2PerBlock(uint256 _b2PerBlock) public onlyRole(ADMIN_ROLE) {
        require(_b2PerBlock > 0, "invalid parameter");

        b2PerBlock = _b2PerBlock;

        emit SetB2PerBlock(_b2PerBlock);
    }

    /**
     * @notice Add a new staking to pool. Can only be called by admin
     * DO NOT add the same staking token more than once. B2 rewards will be messed up if you do
     */
    function addPool(address _stTokenAddress, uint256 _poolWeight, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks,  bool _withUpdate) public onlyRole(ADMIN_ROLE) {
        // Default the first pool to be BTC pool, so the first pool must be added with stTokenAddress = address(0x0)
        if (pool.length > 0) {
            require(_stTokenAddress != address(0x0), "invalid staking token address");
        } else {
            require(_stTokenAddress == address(0x0), "invalid staking token address");
        }
        // allow the min deposit amount equal to 0
        //require(_minDepositAmount > 0, "invalid min deposit amount");
        require(_unstakeLockedBlocks > 0, "invalid withdraw locked blocks");
        require(block.number < endBlock, "Already ended");

        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalPoolWeight = totalPoolWeight + _poolWeight;

        pool.push(Pool({
            stTokenAddress: _stTokenAddress,
            poolWeight: _poolWeight,
            lastRewardBlock: lastRewardBlock,
            accB2PerST: 0,
            stTokenAmount: 0,
            minDepositAmount: _minDepositAmount,
            unstakeLockedBlocks: _unstakeLockedBlocks
        }));

        emit AddPool(_stTokenAddress, _poolWeight, lastRewardBlock, _minDepositAmount, _unstakeLockedBlocks);
    }

    /**
     * @notice Update the given pool's info (minDepositAmount and unstakeLockedBlocks). Can only be called by admin.
     */
    function updatePool(uint256 _pid, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        pool[_pid].minDepositAmount = _minDepositAmount;
        pool[_pid].unstakeLockedBlocks = _unstakeLockedBlocks;

        emit UpdatePoolInfo(_pid, _minDepositAmount, _unstakeLockedBlocks);
    }

    /**
     * @notice Update the given pool's weight. Can only be called by admin.
     */
    function setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        require(_poolWeight > 0, "invalid pool weight");
        
        if (_withUpdate) {
            massUpdatePools();
        }

        totalPoolWeight = totalPoolWeight - pool[_pid].poolWeight + _poolWeight;
        pool[_pid].poolWeight = _poolWeight;

        emit SetPoolWeight(_pid, _poolWeight, totalPoolWeight);
    }

    // ************************************** QUERY FUNCTION **************************************

    /**
     * @notice Get the length/amount of pool
     */
    function poolLength() external view returns(uint256) {
        return pool.length;
    }

    /**
     * @notice Return reward multiplier over given _from to _to block. [_from, _to)
     *
     * @param _from    From block number (included)
     * @param _to      To block number (exluded)
     */
    function getMultiplier(uint256 _from, uint256 _to) public view returns(uint256 multiplier) {
        require(_from <= _to, "invalid block range");
        if (_from < startBlock) {_from = startBlock;}
        if (_to > endBlock) {_to = endBlock;}
        require(_from <= _to, "end block must be greater than start block");
        bool success;
        (success, multiplier) = (_to - _from).tryMul(b2PerBlock);
        require(success, "multiplier overflow");
    }

    /**
     * @notice Get pending B2 amount of user in pool
     */
    function pendingB2(uint256 _pid, address _user) external checkPid(_pid) view returns(uint256) {
        return pendingB2ByBlockNumber(_pid, _user, block.number);
    }

    /**
     * @notice Get pending B2 amount of user by block number in pool
     */
    function pendingB2ByBlockNumber(uint256 _pid, address _user, uint256 _blockNumber) public checkPid(_pid) view returns(uint256) {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_user];
        uint256 accB2PerST = pool_.accB2PerST;
        uint256 stSupply = pool_.stTokenAmount;

        if (_blockNumber > pool_.lastRewardBlock && stSupply != 0) {
            uint256 multiplier = getMultiplier(pool_.lastRewardBlock, _blockNumber);
            uint256 b2ForPool = multiplier * pool_.poolWeight / totalPoolWeight;
            accB2PerST = accB2PerST + b2ForPool * (1 ether) / stSupply;
        }

        return user_.stAmount * accB2PerST / (1 ether) - user_.finishedB2 + user_.pendingB2;
    }

    /**
     * @notice Get the staking amount of user
     */
    function stakingBalance(uint256 _pid, address _user) external checkPid(_pid) view returns(uint256) {
        return user[_pid][_user].stAmount;
    }

    /**
     * @notice Get the withdraw amount info, including the locked unstake amount and the unlocked unstake amount
     */
    function withdrawAmount(uint256 _pid, address _user) public checkPid(_pid) view returns(uint256 requestAmount, uint256 pendingWithdrawAmount) {
        User storage user_ = user[_pid][_user];

        for (uint256 i = 0; i < user_.requests.length; i++) {
            if (user_.requests[i].unlockBlocks <= block.number) {
                pendingWithdrawAmount = pendingWithdrawAmount + user_.requests[i].amount;
            }
            requestAmount = requestAmount + user_.requests[i].amount;
        }
    }

    // ************************************** PUBLIC FUNCTION **************************************

    /**
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function updatePool(uint256 _pid) public checkPid(_pid) {
        Pool storage pool_ = pool[_pid];

        if (block.number <= pool_.lastRewardBlock) {
            return;
        }

        (bool success1, uint256 totalB2) = getMultiplier(pool_.lastRewardBlock, block.number).tryMul(pool_.poolWeight);
        require(success1, "totalB2 mul poolWeight overflow");

        (success1, totalB2) = totalB2.tryDiv(totalPoolWeight);
        require(success1, "totalB2 div totalPoolWeight overflow");

        uint256 stSupply = pool_.stTokenAmount;
        if (stSupply > 0) {
            (bool success2, uint256 totalB2_) = totalB2.tryMul(1 ether);
            require(success2, "totalB2 mul 1 ether overflow");

            (success2, totalB2_) = totalB2_.tryDiv(stSupply);
            require(success2, "totalB2 div stSupply overflow");

            (bool success3, uint256 accB2PerST) = pool_.accB2PerST.tryAdd(totalB2_);
            require(success3, "pool accB2PerST overflow");
            pool_.accB2PerST = accB2PerST;
        }

        pool_.lastRewardBlock = block.number;

        emit UpdatePool(_pid, pool_.lastRewardBlock, totalB2);
    }

    /**
     * @notice Update reward variables for all pools. Be careful of gas spending!
     */
    function massUpdatePools() public {
        uint256 length = pool.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    /**
     * @notice Deposit staking BTC for B2 rewards
     */
    function depositBTC() public whenNotPaused() payable {
        Pool storage pool_ = pool[BTC_PID];
        require(pool_.stTokenAddress == address(0x0), "invalid staking token address");

        uint256 _amount = msg.value;
        require(_amount >= pool_.minDepositAmount, "deposit amount is too small");

        _deposit(BTC_PID, _amount);
    }

    /**
     * @notice Deposit staking token for B2 rewards
     * Before depositing, user needs approve this contract to be able to spend or transfer their staking tokens
     *
     * @param _pid       Id of the pool to be deposited to
     * @param _amount    Amount of staking tokens to be deposited
     */
    function deposit(uint256 _pid, uint256 _amount) public whenNotPaused() checkPid(_pid) {
        require(_pid != 0, "deposit not support BTC staking");
        Pool storage pool_ = pool[_pid];
        require(_amount > pool_.minDepositAmount, "deposit amount is too small");

        if(_amount > 0) {
            IERC20(pool_.stTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        }

        _deposit(_pid, _amount);
    }

    /**
     * @notice Unstake staking tokens
     *
     * @param _pid       Id of the pool to be withdrawn from
     * @param _amount    amount of staking tokens to be withdrawn
     */
    function unstake(uint256 _pid, uint256 _amount) public whenNotPaused() checkPid(_pid) whenNotWithdrawPaused() {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        require(user_.stAmount >= _amount, "Not enough staking token balance");

        updatePool(_pid);

        uint256 pendingB2_ = user_.stAmount * pool_.accB2PerST / (1 ether) - user_.finishedB2;

        if(pendingB2_ > 0) {
            user_.pendingB2 = user_.pendingB2 + pendingB2_;
        }

        if(_amount > 0) {
            user_.stAmount = user_.stAmount - _amount;
            user_.requests.push(UnstakeRequest({
                amount: _amount,
                unlockBlocks: block.number + pool_.unstakeLockedBlocks
            }));
        }

        pool_.stTokenAmount = pool_.stTokenAmount - _amount;
        user_.finishedB2 = user_.stAmount * pool_.accB2PerST / (1 ether);

        emit RequestUnstake(msg.sender, _pid, _amount);
    }

    /**
     * @notice Withdraw the unlock unstake amount
     *
     * @param _pid       Id of the pool to be withdrawn from
     */
    function withdraw(uint256 _pid) public whenNotPaused() checkPid(_pid) whenNotWithdrawPaused() {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        uint256 pendingWithdraw_;
        uint256 popNum_;
        for (uint256 i = 0; i < user_.requests.length; i++) {
            if (user_.requests[i].unlockBlocks > block.number) {
                break;
            }
            pendingWithdraw_ = pendingWithdraw_ + user_.requests[i].amount;
            popNum_++;
        }

        for (uint256 i = 0; i < user_.requests.length - popNum_; i++) {
            user_.requests[i] = user_.requests[i + popNum_];
        }

        for (uint256 i = 0; i < popNum_; i++) {
            user_.requests.pop();
        }

        if (pendingWithdraw_ > 0) {
            if (pool_.stTokenAddress == address(0x0)) {
                _safeBTCTransfer(msg.sender, pendingWithdraw_);
            } else {
                IERC20(pool_.stTokenAddress).safeTransfer(msg.sender, pendingWithdraw_);
            }
        }

        emit Withdraw(msg.sender, _pid, pendingWithdraw_, block.number);
    }

    /**
     * @notice Claim B2 tokens reward
     *
     * @param _pid       Id of the pool to be claimed from
     */
    function claim(uint256 _pid) public whenNotPaused() checkPid(_pid) whenNotClaimPaused() {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        updatePool(_pid);

        uint256 pendingB2_ = user_.stAmount * pool_.accB2PerST / (1 ether) - user_.finishedB2 + user_.pendingB2;

        if(pendingB2_ > 0) {
            user_.pendingB2 = 0;
            _safeB2Transfer(msg.sender, pendingB2_);
        }

        user_.finishedB2 = user_.stAmount * pool_.accB2PerST / (1 ether);

        emit Claim(msg.sender, _pid, pendingB2_);
    }

    // ************************************** INTERNAL FUNCTION **************************************

    /**
     * @notice Deposit staking token for B2 rewards
     *
     * @param _pid       Id of the pool to be deposited to
     * @param _amount    Amount of staking tokens to be deposited
     */
    function _deposit(uint256 _pid, uint256 _amount) internal {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        updatePool(_pid);

        if (user_.stAmount > 0) {
            // uint256 accST = user_.stAmount.mulDiv(pool_.accB2PerST, 1 ether);
            (bool success1, uint256 accST) = user_.stAmount.tryMul(pool_.accB2PerST);
            require(success1, "user stAmount mul accB2PerST overflow");
            (success1, accST) = accST.tryDiv(1 ether);
            require(success1, "accST div 1 ether overflow");
            
            (bool success2, uint256 pendingB2_) = accST.trySub(user_.finishedB2);
            require(success2, "accST sub finishedB2 overflow");

            if(pendingB2_ > 0) {
                (bool success3, uint256 _pendingB2) = user_.pendingB2.tryAdd(pendingB2_);
                require(success3, "user pendingB2 overflow");
                user_.pendingB2 = _pendingB2;
            }
        }

        if(_amount > 0) {
            (bool success4, uint256 stAmount) = user_.stAmount.tryAdd(_amount);
            require(success4, "user stAmount overflow");
            user_.stAmount = stAmount;
        }

        (bool success5, uint256 stTokenAmount) = pool_.stTokenAmount.tryAdd(_amount);
        require(success5, "pool stTokenAmount overflow");
        pool_.stTokenAmount = stTokenAmount;

        // user_.finishedB2 = user_.stAmount.mulDiv(pool_.accB2PerST, 1 ether);
        (bool success6, uint256 finishedB2) = user_.stAmount.tryMul(pool_.accB2PerST);
        require(success6, "user stAmount mul accB2PerST overflow");

        (success6, finishedB2) = finishedB2.tryDiv(1 ether);
        require(success6, "finishedB2 div 1 ether overflow");

        user_.finishedB2 = finishedB2;

        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     * @notice Safe B2 transfer function, just in case if rounding error causes pool to not have enough B2s
     *
     * @param _to        Address to get transferred B2s
     * @param _amount    Amount of B2 to be transferred
     */
    function _safeB2Transfer(address _to, uint256 _amount) internal {
        uint256 B2Bal = B2.balanceOf(address(this));

        if (_amount > B2Bal) {
            B2.transfer(_to, B2Bal);
        } else {
            B2.transfer(_to, _amount);
        }
    }

    /**
     * @notice Safe BTC transfer function
     *
     * @param _to        Address to get transferred BTC
     * @param _amount    Amount of BTC to be transferred
     */
    function _safeBTCTransfer(address _to, uint256 _amount) internal {
        (bool success, bytes memory data) = address(_to).call{
            value: _amount
        }("");

        require(success, "BTC transfer call failed");
        if (data.length > 0) {
            require(
                abi.decode(data, (bool)),
                "BTC transfer operation did not succeed"
            );
        }
    }
}