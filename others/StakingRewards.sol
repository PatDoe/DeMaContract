// StakingRewards: HT: 0x15F342232657208a17d09C99Bb7A758165145D7B
// StakingRewardsFactory: 0x2b5Fa4d7BDDE20227Fb5094973DbC67962D226C7

pragma solidity ^0.6.0;


// import "@openzeppelin/contracts/access/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
// import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract RewardsDistributionRecipient {
    address public rewardsDistribution;

    function notifyRewardAmount(uint256 reward) external;

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
        _;
    }
}

contract StakingRewards is IStakingRewards, RewardsDistributionRecipient, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public rewardsToken;
    IERC20 public stakingToken;

    uint256 public startTime = 0;
    uint256 public lastUpdateTime;

    uint256 public rewardsed = 0;           // Total reward token minted.
    uint256 public periodFinish = 0;        // Each period finished time
    uint256 public rewardRate = 0;          //
    uint256 public rewardsDuration = 7 days;
    uint256 public rewardPerTokenStored;
    uint256 public rewardsPaid = 0;
    uint256 private _totalSupply;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    mapping(address => uint256) private _balances;

    // Different with LP staking rewards
    uint256 public totalRewards = 0;        // Total rewards in will mint for this address.
    uint256 private rewardsNext = 0;        // Next period rewards.
    uint256 private leftRewardTimes = 12;   // Number of halve period.

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        uint256 _rewardAmount,
        uint256 _startTime
    ) public {
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;
        totalRewards = _rewardAmount;
        startTime = _startTime;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    // Return current reward time.
    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    // 
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
            );
    }

    function earned(address account) public view returns (uint256) {
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) checkhalve checkStart {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) checkhalve checkStart {
        require(amount > 0, "Cannot withdraw 0");
        require(_balances[msg.sender] >= amount, "not enough");

        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) checkhalve checkStart {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            rewardsPaid = rewardsPaid.add(reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier checkhalve(){
        if (block.timestamp >= periodFinish && leftRewardTimes > 0) {
            leftRewardTimes = leftRewardTimes.sub(1);
            uint256 reward = leftRewardTimes == 0 ? totalRewards.sub(rewardsed) : rewardsNext;
            rewardsToken.mint(address(this), reward);
            rewardsed = rewardsed.add(reward);
            rewardRate = reward.div(rewardsDuration);
            periodFinish = block.timestamp.add(rewardsDuration);
            rewardsNext = leftRewardTimes > 0 ? rewardsNext.mul(70).div(100) : 0;
            emit RewardAdded(reward);
        }
        _;
    }

    modifier checkStart(){
        require(block.timestamp > startTime,"not start");
        _;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function burn(uint256 amount) external onlyRewardsDistribution {
        leftRewardTimes = 0;
        rewardsNext = 0;
        rewardsToken.burn(address(this), amount);
    }

    // How many reward token mint for this address.
    function notifyRewardAmount(uint256 reward) external onlyRewardsDistribution updateReward(address(0)) {
        require(rewardsed == 0, "reward already inited");
        if (block.timestamp >= periodFinish) {
            // First time
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }
        rewardsToken.mint(address(this), reward);
        rewardsed = reward;
        rewardsNext = rewardsed.mul(70).div(100);
        leftRewardTimes = leftRewardTimes.sub(1);
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event Burn(uint256 amount);
}

contract StakingRewardsFactory is Ownable {
    // immutables
    address public rewardsToken;

    // the staking tokens for which the rewards contract has been deployed
    address[] public stakingTokens;

    // info about rewards for a particular staking token
    struct StakingRewardsInfo {
        address stakingRewards;
        uint rewardAmount;
    }

    // rewards info by staking token
    mapping(address => StakingRewardsInfo) public stakingRewardsInfoByStakingToken;

    constructor(
        address _rewardsToken
    ) Ownable() public {
        rewardsToken = _rewardsToken;
    }

    ///// permissioned functions

    // deploy a staking reward contract for the staking token, and store the total reward amount
    function deploy(address stakingToken, uint rewardAmount, uint256 startTime) public onlyOwner {
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[stakingToken];
        require(info.stakingRewards == address(0), 'StakingRewardsFactory::deploy: already deployed');
        info.stakingRewards = address(new StakingRewards(/*_rewardsDistribution=*/ address(this),
            rewardsToken, stakingToken, rewardAmount, startTime));
        stakingTokens.push(stakingToken);
    }

    // notify initial reward amount for an individual staking token.
    function notifyRewardAmount(address stakingToken, uint256 rewardAmount) public onlyOwner {
        require(rewardAmount > 0, 'amount should > 0');
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[stakingToken];
        require(info.stakingRewards != address(0), 'StakingRewardsFactory::notifyRewardAmount: not deployed');
        if (info.rewardAmount <= 0) {
            info.rewardAmount = rewardAmount;
            StakingRewards(info.stakingRewards).notifyRewardAmount(rewardAmount);
        }
    }

    function burn(address stakingToken, uint256 amount) public onlyOwner {
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[stakingToken];
        require(info.stakingRewards != address(0), 'StakingRewardsFactory::burn: not deployed');
        StakingRewards(info.stakingRewards).burn(amount);
    }

}