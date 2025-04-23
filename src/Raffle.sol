// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

/**
 * @title 一个抽奖合约
 * @author fanshuai
 * @notice  这个合约是为了创建一个抽奖合约
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle_NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle_NotOpen();
    error Raffle__UpkeepNotNeeded(uint256, uint256, uint256);

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    //区块确认数
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    //随机数个数
    uint32 private constant NUM_WORDS = 1;
    //门票单价
    uint256 private immutable i_entranceFee;
    //抽奖持续时间，以秒为单位
    uint256 private immutable i_interval;
    //vrf合约地址
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    //
    bytes32 private immutable i_gasLane;
    //订阅vrf的订阅id
    uint64 private immutable i_subscriptionId;

    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    event EnterdRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 _entranceFee,
        uint256 _interval,
        address _vrfCoordinator,
        bytes32 _gasLane,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        i_entranceFee = _entranceFee;
        i_interval = _interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        i_gasLane = _gasLane;
        i_subscriptionId = _subscriptionId;
        i_callbackGasLimit = _callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle_NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_NotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnterdRaffle(msg.sender);
    }

    /**
     * chainlink自动化节点调用判断是否执行unkeep的时间的函数
     * 以下情况会触发unkeep
     * 1. 当前时间与lastTimeStamp的时间差大于interval
     * 2. 合约抽奖状态为open
     * 3. 有人参数抽奖 且合约中有余额
     * 4. chainlink订阅有相应的link资金
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasPlayers && hasBalance);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit  RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(recentWinner);
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns(RaffleState){
        return s_raffleState;
    }

    function getPlayer(uint256 index) external view returns(address){
        return s_players[index];
    }

    function getRecentWinner()   external view returns(address) {
        return s_recentWinner;
    } 

    function getLengthOfPlayers() external view returns(uint256){
        return s_players.length;
    }

    function getLastTimeStamp() external view returns(uint256){
        return s_lastTimeStamp;
    }
}
