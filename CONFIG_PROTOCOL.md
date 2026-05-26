# meds.conf 数据安检协议

本协议规定了 Web UI 与 后台监控系统间的数据交互格式，以确保系统运行的健壮性。

## 1. 存储位置
- 路径: `/app/Linux-Course-Project/meds.conf`

## 2. 数据格式 (KEY=VALUE)
所有配置采用键值对格式，每行一个配置：
- TIME=HH:MM (例如: 14:30)
- DRUG_NAME=Name (例如: VitaminC)
- STATUS=ENABLE/DISABLE

## 3. 安检校验规则
- 解析器 parser.sh 在读取时将执行以下校验：
  - 必须包含必要的 KEY
  - 时间格式必须符合 HH:MM 正则匹配
  - 状态位仅允许 ENABLE 或 DISABLE

## 4. 协作约定
- Web 端在写入前需确保格式符合上述要求。
- 提供 `parser.sh` 进行热加载与校验。
