# 业务规格与不变量

## 角色

| 角色 | 权限 | 生产建议 |
| --- | --- | --- |
| Admin | 配置角色、替换登记/合规模块 | 多签 + timelock |
| Registrar | 登记、更新、撤销投资者身份 | KYC/AML 服务账户 |
| Compliance Officer | 国家、阻断、持仓规则 | 合规团队多签 |
| Token Agent | 铸造、销毁、冻结、强制转移 | 受限运营账户 |
| Fund Manager | 处理订单、暂停基金 | 运营多签 |
| NAV Oracle | 更新单位净值 | 独立价格发布流程 |

## 身份与转账规则

- 接收证券份额的地址必须身份有效、未被阻断且司法辖区获准。
- 普通转账的发送方也必须身份有效，且双方不得被冻结。
- 铸造必须通过接收方规则；强制转移绕过发送方冻结，但仍校验接收方。
- 冻结份额不得超过余额；任何销毁/转移后都必须保持该关系。

## 申购状态机

`None -> Pending -> Processed | Cancelled`

- 请求时先托管支付资产，并记录 `minShares`。
- 处理时按当前 NAV 计算份额；低于 `minShares` 则整笔回滚。
- 取消只能由订单投资者发起并全额退款。
- 所有 Pending 申购之和记为 `pendingSubscriptionAssets`，不得用于兑付其他人的赎回。

## 赎回状态机

`None -> Pending -> Processed | Cancelled`

- 请求时将份额托管到基金合约，并记录 `minAssets`。
- 处理时按当前 NAV 计算支付额，检查滑点与可用流动性，然后销毁份额并付款。
- 取消只能由订单投资者发起，托管份额原路返还。

## DvP 订单

签名覆盖 seller、buyer、证券/支付 token、双方数量、nonce、deadline，并绑定 `chainId` 与结算合约地址。订单只允许使用一次；任一资产转移失败时整笔交易回滚。

## 核心安全性质

1. `sum(tracked balances) == totalSupply`。
2. ghost mint 减 ghost burn 等于 `totalSupply`。
3. `frozenTokens(account) <= balanceOf(account)`。
4. 随机调用后持币地址仍通过身份验证。
5. Pending 订单不能被重复处理或取消。
6. Pending 申购资金始终可被完整退款。
7. DvP nonce 不能结算两次。
8. DvP 任一腿失败时不得只完成另一腿。
