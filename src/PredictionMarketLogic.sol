// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract PredictionMarket is Ownable, ReentrancyGuard {
    using Strings for uint256;

    enum MarketOutcome { Undecided, Yes, No, Draw }
    enum MarketCategory { General, Sports, Politics, Finance, Technology, Other }

    struct MarketMetadata {
        string title;
        string description;
        string resolutionSource;
        MarketCategory category;
        string[] tags;
    }

    struct MarketStats {
        uint256 uniqueVoters;
        uint256 totalTransactions;
        uint256 avgVoteAmount;
        uint256 largestVote;
        address largestVoter;
        uint256 lastUpdateTime;
    }

    struct Market {
        MarketMetadata metadata;
        MarketStats stats;
        uint256 startTime;
        uint256 endTime;
        MarketOutcome outcome;
        uint256 totalYesAmount;
        uint256 totalNoAmount;
        IERC20 votingToken;
        uint256 feePercentage;  //
        bool feeClaimed;
        mapping(address => uint256) yesVotes;
        mapping(address => uint256) noVotes;
        mapping(address => bool) hasVoted;
        mapping(address => bool) hasClaimed;
    }

    mapping(uint256 => Market) public markets;
    uint256 public marketCount;
    uint256 public defaultFeePercentage;  // デフォルト手数料率（1000 = 10%）
    address public feeCollector;
    
    // イベント類
    event MarketCreated(
        uint256 indexed marketId,
        string title,
        uint256 startTime,
        uint256 endTime,
        address votingToken,
        MarketCategory category
    );
    event VoteCast(
        uint256 indexed marketId,
        address indexed voter,
        bool isYes,
        uint256 amount,
        uint256 timestamp
    );
    event MarketResolved(
        uint256 indexed marketId,
        MarketOutcome outcome,
        string resolutionDetails
    );
    event RewardClaimed(
        uint256 indexed marketId,
        address indexed voter,
        uint256 amount,
        uint256 feeAmount
    );
    event VotingTokenUpdated(uint256 indexed marketId, address newToken);
    event FeePercentageUpdated(uint256 indexed marketId, uint256 newFeePercentage);
    event DefaultFeePercentageUpdated(uint256 newDefaultFeePercentage);
    event FeeCollectorUpdated(address newFeeCollector);
    event MarketCancelled(uint256 indexed marketId, string reason);
    event FeeClaimed(uint256 indexed marketId, uint256 amount);

    constructor() Ownable(msg.sender) {
        feeCollector = msg.sender;
    }

    // 新しい市場を作成
    function createMarket(
        string memory title,
        string memory description,
        string memory resolutionSource,
        MarketCategory category,
        string[] memory tags,
        uint256 startTime,
        uint256 duration,
        address votingToken,
        uint256 customFeePercentage
    ) external onlyOwner returns (uint256) {
        require(startTime >= block.timestamp, "Start time must be in the future");
        require(duration > 0, "Duration must be positive");
        require(votingToken != address(0), "Invalid token address");
        require(customFeePercentage <= 3000, "Fee percentage too high"); // 最大30%

        uint256 marketId = marketCount++;
        Market storage market = markets[marketId];
        
        // メタデータの設定
        market.metadata.title = title;
        market.metadata.description = description;
        market.metadata.resolutionSource = resolutionSource;
        market.metadata.category = category;
        market.metadata.tags = tags;

        // 市場パラメータの設定
        market.startTime = startTime;
        market.endTime = startTime + duration;
        market.votingToken = IERC20(votingToken);
        market.feePercentage = customFeePercentage > 0 ? customFeePercentage : defaultFeePercentage;

        // 統計情報の初期化
        market.stats.lastUpdateTime = block.timestamp;

        emit MarketCreated(
            marketId,
            title,
            startTime,
            market.endTime,
            votingToken,
            category
        );
        return marketId;
    }

    // 統計情報の更新
    function _updateMarketStats(
        uint256 marketId,
        address voter,
        uint256 amount
    ) internal {
        Market storage market = markets[marketId];
        MarketStats storage stats = market.stats;

        if (!market.hasVoted[voter]) {
            stats.uniqueVoters++;
            market.hasVoted[voter] = true;
        }

        stats.totalTransactions++;
        
        // 平均投票額の更新
        stats.avgVoteAmount = (
            (stats.avgVoteAmount * (stats.totalTransactions - 1) + amount)
            / stats.totalTransactions
        );

        // 最大投票の更新
        if (amount > stats.largestVote) {
            stats.largestVote = amount;
            stats.largestVoter = voter;
        }

        stats.lastUpdateTime = block.timestamp;
    }

    // 投票を実行
    function vote(uint256 marketId, bool isYes, uint256 amount) external nonReentrant {
        Market storage market = markets[marketId];
        require(block.timestamp >= market.startTime, "Market not started");
        require(block.timestamp < market.endTime, "Market has ended");
        require(market.outcome == MarketOutcome.Undecided, "Market already resolved");
        require(amount > 0, "Amount must be positive");

        // トークンの転送
        require(
            market.votingToken.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        // 投票を記録
        if (isYes) {
            market.yesVotes[msg.sender] += amount;
            market.totalYesAmount += amount;
        } else {
            market.noVotes[msg.sender] += amount;
            market.totalNoAmount += amount;
        }

        // 統計情報の更新
        _updateMarketStats(marketId, msg.sender, amount);

        emit VoteCast(marketId, msg.sender, isYes, amount, block.timestamp);
    }

    // 市場を解決
    function resolveMarket(
        uint256 marketId,
        MarketOutcome outcome,
        string memory resolutionDetails
    ) external onlyOwner {
        Market storage market = markets[marketId];
        require(block.timestamp >= market.endTime, "Market not ended yet");
        require(market.outcome == MarketOutcome.Undecided, "Market already resolved");
        require(
            outcome == MarketOutcome.Yes ||
            outcome == MarketOutcome.No ||
            outcome == MarketOutcome.Draw,
            "Invalid outcome"
        );

        market.outcome = outcome;
        emit MarketResolved(marketId, outcome, resolutionDetails);
    }

    // 報酬を請求
    function claimReward(uint256 marketId) external nonReentrant {
        Market storage market = markets[marketId];
        require(market.outcome != MarketOutcome.Undecided, "Market not resolved yet");
        require(!market.hasClaimed[msg.sender], "Reward already claimed");

        uint256 reward = 0;
        uint256 feeAmount = 0;

        if (market.outcome == MarketOutcome.Draw) {
            // 引き分けの場合は投票額を返還
            reward = market.yesVotes[msg.sender] + market.noVotes[msg.sender];
        } else {
            bool isWinner = (
                market.outcome == MarketOutcome.Yes && market.yesVotes[msg.sender] > 0
            ) || (
                market.outcome == MarketOutcome.No && market.noVotes[msg.sender] > 0
            );

            if (isWinner) {
                uint256 winningAmount = market.outcome == MarketOutcome.Yes
                    ? market.yesVotes[msg.sender]
                    : market.noVotes[msg.sender];
                uint256 totalWinningAmount = market.outcome == MarketOutcome.Yes
                    ? market.totalYesAmount
                    : market.totalNoAmount;
                uint256 totalAmount = market.totalYesAmount + market.totalNoAmount;

                reward = (winningAmount * totalAmount) / totalWinningAmount;
            }
        }

        require(reward > 0, "No reward to claim");

        // 手数料の計算と控除
        if (market.feePercentage > 0) {
            feeAmount = (reward * market.feePercentage) / 10000;
            reward -= feeAmount;
        }

        market.hasClaimed[msg.sender] = true;

        // 報酬の転送
        require(market.votingToken.transfer(msg.sender, reward), "Reward transfer failed");
        if (feeAmount > 0) {
            require(
                market.votingToken.transfer(feeCollector, feeAmount),
                "Fee transfer failed"
            );
        }

        emit RewardClaimed(marketId, msg.sender, reward, feeAmount);
    }

    // 管理者機能: デフォルト手数料率の更新
    function updateDefaultFeePercentage(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 3000, "Fee percentage too high"); // 最大30%
        defaultFeePercentage = newFeePercentage;
        emit DefaultFeePercentageUpdated(newFeePercentage);
    }

    // 管理者機能: 手数料受取アドレスの更新
    function updateFeeCollector(address newFeeCollector) external onlyOwner {
        require(newFeeCollector != address(0), "Invalid address");
        feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }

    // 管理者機能: 特定の市場の手数料率を更新
    function updateMarketFeePercentage(
        uint256 marketId,
        uint256 newFeePercentage
    ) external onlyOwner {
        require(newFeePercentage <= 3000, "Fee percentage too high");
        Market storage market = markets[marketId];
        require(market.outcome == MarketOutcome.Undecided, "Market already resolved");
        
        market.feePercentage = newFeePercentage;
        emit FeePercentageUpdated(marketId, newFeePercentage);
    }

    // 管理者機能: 市場をキャンセル（緊急時用）
    function cancelMarket(uint256 marketId, string memory reason) external onlyOwner {
        Market storage market = markets[marketId];
        require(market.outcome == MarketOutcome.Undecided, "Market already resolved");
        
        market.outcome = MarketOutcome.Draw;  // Draw扱いにして全額返還可能に
        emit MarketCancelled(marketId, reason);
    }

    // 市場の詳細情報を取得
    function getMarketDetails(uint256 marketId) external view returns (
        string memory title,
        string memory description,
        string memory resolutionSource,
        MarketCategory category,
        string[] memory tags,
        uint256 startTime,
        uint256 endTime,
        MarketOutcome outcome,
        uint256 totalYesAmount,
        uint256 totalNoAmount,
        address votingToken,
        uint256 feePercentage
    ) {
        Market storage market = markets[marketId];
        return (
            market.metadata.title,
            market.metadata.description,
            market.metadata.resolutionSource,
            market.metadata.category,
            market.metadata.tags,
            market.startTime,
            market.endTime,
            market.outcome,
            market.totalYesAmount,
            market.totalNoAmount,
            address(market.votingToken),
            market.feePercentage
        );
    }

    // 市場の統計情報を取得
    function getMarketStats(uint256 marketId) external view returns (
        uint256 uniqueVoters,
        uint256 totalTransactions,
        uint256 avgVoteAmount,
        uint256 largestVote,
        address largestVoter,
        uint256 lastUpdateTime
    ) {
        MarketStats storage stats = markets[marketId].stats;
        return (
            stats.uniqueVoters,
            stats.totalTransactions,
            stats.avgVoteAmount,
            stats.largestVote,
            stats.largestVoter,
            stats.lastUpdateTime
        );
    }

    // ユーザーの投票状況を取得
    function getUserVotes(uint256 marketId, address user) external view returns (
        uint256 yesVotes,
        uint256 noVotes,
        bool hasVoted,
        bool hasClaimed
    ) {
        Market storage market = markets[marketId];
        return (
            market.yesVotes[user],
            market.noVotes[user],
            market.hasVoted[user],
            market.hasClaimed[user]
        );
    }
}