# 设备同步协议草案 v0.1

状态：proposal

## 目标

在不向 Relay 暴露 D2/D3 明文的前提下，实现离线写入、缺口检测、历史补采、设备撤销、显式冲突和删除传播。

## 身份与序列

每个设备拥有 `device_id`、签名公钥、加密公钥、单调 `device_seq` 和状态 `active/revoked/retired`。事件 ID 全局唯一，设备序列只用于缺口检测，不用于决定业务胜负。

## Sync Envelope

Relay 可见的最小字段：协议版本、account pseudonym、sender device、recipient group/epoch、device sequence range、ciphertext length、upload time、opaque cursor、ciphertext、signature。

业务 event_type、对象 ID、敏感度、时间、Consent 和 payload 全部在密文内。需要进一步评估长度和时间造成的流量分析风险。

## 上传

1. 本地事务提交 event + projection + outbox；
2. Sync Worker 将若干事件打包，使用当前 account epoch key 加密；
3. 使用设备签名密钥签名 envelope；
4. Relay 幂等保存并返回 cursor/ack；
5. ack 后 outbox 标记 delivered，但本地事件永不因上传删除。

## 下载与缺口补采

1. 客户端以 opaque cursor 拉取；
2. 验证发送设备、epoch、签名和 sequence；
3. sequence 缺口生成 `sync.gap.detected` 并请求范围补采；
4. 解密后执行 Schema、Consent、敏感度、状态机校验；
5. 合法事件进入 inbox-to-event-store 原子事务；
6. 不可交换并发生成 `conflict.detected`。

## 设备撤销

- 撤销产生签名的 device.revoked 控制事件；
- 新 epoch key 不分发给撤销设备；
- 撤销不承诺抹掉设备此前已解密的数据；
- Primary Device 必须能够查看设备列表、最后同步和权限范围。

## Restricted Collector

只拥有写入限定事件类型和加密上传的 capability。默认不持有 account epoch 解密密钥；可使用“只写包封密钥”让其加密给 Vault 设备，但不能解密历史包。

## 删除传播

删除事件优先同步；接收端建立 deletion barrier，清除本地 Blob/索引/Snapshot，并回传 deletion receipt。Relay 删除密文对象后只保留不含业务标识的最小合规记录。

## 未决协议点

- 单用户多设备的 group key/每设备封装方案；
- 新设备加入和历史密钥授权范围；
- 恢复设备与恢复材料；
- metadata padding、批量大小和同步频率；
- Relay 保留期、ack 垃圾回收和离线设备上限。

