# PredictionMarket.sol

## 📋 概要

予測市場 (ex.Polymarket) の基本的な機能を持ったコントラクトです。

メインネットでの実装の際にはSignature等でリエトラ攻撃の対策を行いましょう。

## 🌟 主な機能

### 管理者向け機能
- 新規市場の作成
- 投票用トークンの設定と変更
- 市場結果の確定
- 手数料設定と管理

### ユーザー向け機能
- Yes/No投票の実行
- 投票状況の確認
- 報酬の請求

---

## 📚 関数リファレンス

### 市場の作成 `createMarket()`
```solidity
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
) external onlyOwner returns (uint256)
```

#### 📝 パラメータ例
```javascript
{
    title: "2024年のBTCは8万ドルを超えるか？",
    description: "2024年12月31日までにBTC価格が8万ドルを超えるかどうかを予測",
    resolutionSource: "CoinGecko BTC/USD価格データ",
    category: 0,  // 0: General
    tags: ["crypto", "bitcoin", "price"],
    startTime: 1704067200,  // 2024-01-01 00:00:00 UTC
    duration: 31536000,     // 1年間（秒）
    votingToken: "0x...",   // ERC20トークンアドレス
    customFeePercentage: 100  // 1.00%
}
```

### 投票実行 `vote()`
```solidity
function vote(
    uint256 marketId,
    bool isYes,
    uint256 amount
) external nonReentrant
```

#### 📝 パラメータ例
```javascript
{
    marketId: 0,
    isYes: true,    // Yes投票
    amount: "1000000000000000000"  // 1トークン（18デシマルの場合）
}
```

### 市場結果確定 `resolveMarket()`
```solidity
function resolveMarket(
    uint256 marketId,
    MarketOutcome outcome,
    string memory resolutionDetails
) external onlyOwner
```

#### 📝 パラメータ例
```javascript
{
    marketId: 0,
    outcome: 1,     // 1: Yes, 2: No, 3: Draw
    resolutionDetails: "2024年12月31日時点でBTC価格は85,000ドルを記録"
}
```

### 報酬請求 `claimReward()`
```solidity
function claimReward(uint256 marketId) external nonReentrant
```

#### 📝 パラメータ例
```javascript
{
    marketId: 0
}
```

### 市場情報取得 `getMarketDetails()`
```solidity
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
)
```

---

## 🔔 イベント一覧

### 市場作成イベント `MarketCreated`
```solidity
event MarketCreated(
    uint256 indexed marketId,
    string title,
    uint256 startTime,
    uint256 endTime,
    address votingToken,
    MarketCategory category
);
```

### 投票実行イベント `VoteCast`
```solidity
event VoteCast(
    uint256 indexed marketId,
    address indexed voter,
    bool isYes,
    uint256 amount,
    uint256 timestamp
);
```

### 市場結果確定イベント `MarketResolved`
```solidity
event MarketResolved(
    uint256 indexed marketId,
    MarketOutcome outcome,
    string resolutionDetails
);
```

---

## 🔒 セキュリティ機能

### リエントランシー攻撃の防止
- OpenZeppelinの`ReentrancyGuard`を使用
- 投票や報酬請求時の安全性を確保

### アクセス制御
- OpenZeppelinの`Ownable`を使用
- 管理者専用機能の保護

### 入力値の検証
- パラメータの妥当性チェック
- 不正な入力値の排除

---

## 💰 手数料システム

| 項目 | 説明 |
|------|------|
| 最大手数料率 | 30.00%（3000） |
| デフォルト手数料率 | 0% |
| 設定単位 | 0.01%（1） |
| 徴収タイミング | 報酬請求時 |

---

## ⚠️ 注意事項

### 投票トークン
- ERC20準拠のトークンのみ使用可能
- トークンのデシマルに注意が必要

### 時間設定
- `startTime`は現在時刻より後
- `duration`は秒単位で指定

### 投票
- 投票したトークンは市場終了まで固定
- 同一市場への複数回投票が可能

### 報酬請求
- 市場確定後のみ請求可能
- 引き分けの場合は投票額を返還
- 報酬請求は一回のみ

---

## 🚀 デプロイ時の考慮事項

1. **ネットワーク選択**
   - メインネット
   - テストネット

2. **初期設定の確認**
   - デフォルト手数料率
   - 管理者アドレス
   - ガス代の見積もり

