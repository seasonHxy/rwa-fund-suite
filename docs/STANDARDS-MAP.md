# 标准映射与差距

## ERC-3643 思路映射

| 能力 | 当前项目 | 仍需补齐 |
| --- | --- | --- |
| 身份登记与 token 分离 | `IdentityRegistry` | ONCHAINID、claims、trusted issuers、claim topics |
| 转账前合规检查 | `ModularCompliance` | 标准接口、可插拔 module 生命周期、批量操作 |
| Agent 操作 | mint/burn/freeze/forced transfer/recovery | 完整事件、标准接口、代理人治理 |
| 转账拒绝原因 | `canTransfer` + reason byte | 与正式标准 reason code/接口逐项兼容 |

## ERC-1400 思路映射

| 能力 | 当前项目 | 仍需补齐 |
| --- | --- | --- |
| 受限转账与可解释性 | 有 | 标准 `canTransfer` / status code 接口 |
| 发行、赎回、控制者操作 | 有核心业务动作 | 标准化 issuance/redemption/controller 接口 |
| 分区 | 无 | `partition` 余额、操作员、分区转移与企业行动 |
| 文档管理 | 无 | prospectus/NAV policy 等文档 URI + hash |

## 推荐迭代顺序

1. 用正式 ERC-3643 实现做接口与行为对照测试，而不是继续扩写“相似接口”。
2. 加入 ERC-1400 partition，用不同分区表达锁定期、投资者类别或发行批次。
3. 将基金改成 UUPS 版本，编写未初始化、非法升级、存储布局兼容测试。
4. 增加 TypeScript 运维层：KYC 入库、订单签名、部署验证、事件索引与每日对账。
5. 加入主网分叉与异常 ERC-20 测试，并用 Slither/形式化性质验证关键不变量。
