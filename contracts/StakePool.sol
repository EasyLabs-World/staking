pragma solidity ^0.4.24;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import './StakeContract.sol';

/* @title Staking Pool Contract */
contract StakePool {
  using SafeMath for uint;

  /** @dev set owner
    */
  address private owner;
  /** @dev owners profits
    */
  uint private ownersBalance;

  /** @dev owners payout percentage in uint
    * 1 = 1%
    */
  uint8 private ownersPayout = 1;

  /** @dev address of staking contract
    */
  address public stakeContract;
  /** @dev staking contract object to interact with existing contract at known
    * location
    */
  StakeContract sc;

  /** @dev track total staked amount
    */
  uint totalStaked;

  /** @dev track total deposited
    */
  uint totalDeposited;

  /** @dev track balances of ether deposited to contract
    */
  mapping(address => uint) private depositedBalances;

  /** @dev track balances of ether staked to contract
    */
  mapping(address => uint) private stakedBalances;

  /** @dev track block.number when ether was staked
    */
  mapping(address => uint) private blockStaked;
  /** @dev track block.number when ether was unstaked
    */
  mapping(address => uint) private blockUnstaked;

  /** @dev track user request to enter next staking period
    */
  mapping(address => uint) private requestStake;
  /** @dev track user request to exit current staking period
    */
  mapping(address => uint) private requestUnStake;

  /** @dev track users
    */
  address[] users;
  /** @dev track index by address added to users
    */
  mapping(address => uint) private userIndex;

  /** @dev contract constructor
    */
  constructor(address _stakeContract) public {
    owner = msg.sender;
    stakeContract = _stakeContract;
    sc = StakeContract(stakeContract);
    // set owner to users[0] because unknown user will return 0 from userIndex
    users.push(owner);
  }

  /** @dev payable fallback
    * it is assumed that only funds received will be from stakeContract
    */
  function () external payable {
    emit FallBackSP(msg.sender, msg.value, block.number);
  }

  /** @dev notify when funds received at contract
    */
  event FallBackSP(
    address sender,
    uint value,
    uint blockNumber
  );

  /** @dev restrict function to only work when called by owner
    * TODO: replace with zeppelin Ownable?
    */
  modifier onlyOwner() {
    require(
      msg.sender == owner,
      "only owner can call this function"
    );
    _;
  }

  /************************ USER MANAGEMENT **********************************/
  /* TODO: create Library?? */
  /** @dev test if user is in current user list
    */
  function isExistingUser(address _user) public view returns (bool) {
    if ( userIndex[_user] == 0) {
      return false;
    }
    return true;
  }

  /** @dev remove a user from users array
    */
  function removeUser(address _user) internal {
    uint index = userIndex[_user];
    // never remove owner from 0 slot in user array
    if (index == 0) return;
    // user is not last user
    if (index < users.length.sub(1)) {
      address lastUser = users[users.length.sub(1)];
      users[index] = lastUser;
      userIndex[lastUser] = index;
    }
    // this line removes last user
    users.length = users.length.sub(1);
  }

  /** @dev add a user to users array
    */
  function addUser(address _user) internal {
    if (_user == owner ) return;
    if (isExistingUser(_user)) return;
    users.push(_user);
    // new user is currently last in users array
    userIndex[_user] = users.length.sub(1);
  }
  /************************ USER MANAGEMENT **********************************/


  /** @dev set staking contract address
    */
  function setStakeContract(address _staker) public onlyOwner {
   stakeContract = _staker;
   sc = StakeContract(stakeContract);
  }

  /** @dev withdraw profits to owner account
    */
  function getOwnersProfits() public onlyOwner {
    require(ownersBalance > 0);
    uint valueWithdrawn = ownersBalance;
    ownersBalance = 0;
    owner.transfer(valueWithdrawn);
    emit NotifyProfitWithdrawal(valueWithdrawn);
  }

  /** @dev notify of owner profit withdraw
    */
  event NotifyProfitWithdrawal(uint valueWithdrawn);

  /** @dev owner only may retreive undistributedFunds value
    */
  function getUndistributedFundsValue() public view onlyOwner returns (uint) {
    return address(this).balance.sub(ownersBalance).sub(totalDeposited);
  }

  /** @dev trigger notification of deposits
    */
  event NotifyDeposit(
    address sender,
    uint amount,
    uint balance);

  /** @dev deposit funds to the contract
    */
  function deposit() public payable {
    addUser(msg.sender);
    depositedBalances[msg.sender] = depositedBalances[msg.sender].add(msg.value);
    emit NotifyDeposit(msg.sender, msg.value, depositedBalances[msg.sender]);
  }

  /** @dev trigger notification of staked amount
    */
  event NotifyStaked(
    address sender,
    uint amount,
    uint blockNum
  );

  /** @dev stake funds to stakeContract
    * http://solidity.readthedocs.io/en/latest/control-structures.html#external-function-calls
    */
  function stake() public {
    // * update mappings
    // * send total balance to stakeContract
    uint toStake;
    for (uint i = 0; i < users.length; i++) {
      uint amount = requestStake[users[i]];
      toStake = toStake.add(amount);
      stakedBalances[users[i]] = stakedBalances[users[i]].add(amount);
      requestStake[users[i]] = 0;
    }

    // track total staked
    totalStaked = totalStaked.add(toStake);

    // this is how to send ether with a call to an external contract
    // sc.deposit.value(toStake)();
    address(sc).transfer(toStake);

    emit NotifyStaked(
      msg.sender,
      toStake,
      block.number
    );
  }

  /** @dev unstake funds from stakeContract
    *
    */
  function unstake() public {
    uint unStake;
    for (uint i = 0; i < users.length; i++) {
      uint amount = requestUnStake[users[i]];
      unStake = unStake.add(amount);
      stakedBalances[users[i]] = stakedBalances[users[i]].sub(amount);
      depositedBalances[users[i]] = depositedBalances[users[i]].add(amount);
      requestUnStake[users[i]] = 0;
    }

    // track total staked
    totalStaked = totalStaked.sub(unStake);

    // sc.withdraw(amount, msg.sender);
    sc.withdraw(unStake);

    emit NotifyStaked(
      msg.sender,
      -unStake,
      block.number
    );
  }

  event NotifyUpdate(
    address user,
    uint previousBalance,
    uint newStakeBalence
  );
  event NotifyEarnings(uint earnings);

  /** @dev calculated new stakedBalances
    */
  function calcNewBalances() public returns (bool) {
    uint totalSC = address(sc).balance;
    uint earnings = totalSC.sub(totalStaked);
    emit NotifyEarnings(earnings);

    if (earnings > 0) {
      for (uint i = 0; i < users.length; i++) {
        uint currentBalance = stakedBalances[users[i]];

        stakedBalances[users[i]] =
          currentBalance.add(
            earnings.mul(99).div(100).mul(currentBalance).div(totalStaked)
          );

        emit NotifyUpdate(users[i], currentBalance, stakedBalances[users[i]]);
      }

      totalStaked = address(sc).balance;
      return true;
    } else {
      return false;
    }
  }

  /** @dev trigger notification of withdrawal
    */
  event NotifyWithdrawal(
    address sender,
    uint startBal,
    uint finalBal,
    uint request);

  /** @dev withdrawal funds out of pool
    * @param wdValue amount to withdraw
    * TODO: this must be a request for withdrawal as un-staking takes time
    * not payable, not receiving funds
    */
  function withdraw(uint wdValue) public {
    require(wdValue > 0);
    require(depositedBalances[msg.sender] >= wdValue);
    uint startBalance = depositedBalances[msg.sender];
    // open zeppelin sub function to ensure no overflow
    depositedBalances[msg.sender] = depositedBalances[msg.sender].sub(wdValue);
    msg.sender.transfer(wdValue);

    emit NotifyWithdrawal(
      msg.sender,
      startBalance,
      depositedBalances[msg.sender],
      wdValue
    );
  }

  /** @dev retreive current state of users funds
    */
  function getState() public view returns (uint[]) {
    uint[] memory state = new uint[](4);
    state[0] = depositedBalances[msg.sender];
    state[1] = requestStake[msg.sender];
    state[2] = requestUnStake[msg.sender];
    state[3] = stakedBalances[msg.sender];
    return state;
  }

  /** @dev retreive balance from contract
    * @return uint current value of deposit
    */
  function getBalance() public view returns (uint) {
    return depositedBalances[msg.sender];
  }

  /** @dev retreive staked balance from contract
    * @return uint current value of stake deposit
    */
  function getStakedBalance() public view returns (uint) {
    return stakedBalances[msg.sender];
  }
  /** @dev retreive stake request balance from contract
    * @return uint current value of stake request
    */
  function getStakeRequestBalance() public view returns (uint) {
    return requestStake[msg.sender];
  }
  /** @dev retreive stake request balance from contract
    * @return uint current value of stake request
    */
  function getUnStakeRequestBalance() public view returns (uint) {
    return requestUnStake[msg.sender];
  }

  /** @dev user can request to enter next staking period
    */
  function requestNextStakingPeriod() public {
    require(depositedBalances[msg.sender] > 0);
    uint amount = depositedBalances[msg.sender];
    depositedBalances[msg.sender] = 0;
    // TODO: add test for adding additional funds to stake pool
    requestStake[msg.sender] = requestStake[msg.sender].add(amount);
    emit NotifyStaked(msg.sender, requestStake[msg.sender], block.number);
  }

  /** @dev user can request to exit at end of current staking period
    */
  function requestExitAtEndOfCurrentStakingPeriod(uint amount) public {
    require(stakedBalances[msg.sender] >= amount);
    requestUnStake[msg.sender] = requestUnStake[msg.sender].add(amount);
    emit NotifyStaked(msg.sender, requestUnStake[msg.sender], block.number);
  }
}

  /* example comments for functions */
    /** @dev Calculates a rectangle's surface and perimeter.
      * @param w Width of the rectangle.
      * @param h Height of the rectangle.
      * @return s The calculated surface.
      * @return p The calculated perimeter.
      */
