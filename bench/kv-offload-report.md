# 分层 KV 卸载实测（速度 ⇄ 上下文曲线）

- 日期：2026-11-14 · 方法：临时实例 :8010 AB 实测（`--no-kv-unified` + `-ot` 层级正则 KV→CPU）· SPRINT-10
- 基线：64K 全 GPU（KV q8_0 · ub2048 · draft-mtp）= **1.3s/200tok** · 22000MiB

## 矩阵结果

| 配置 | 显存 | 生成 200tok | 备注 |
|------|------|-------------|------|
| 128K · 卸16层起 · 无draft | 21416MiB | **40.1s** | 首测含长尾噪声，但量级确证：PCIe 读 KV 代价大 |
| 128K · 卸32层起 · 无draft | 21442MiB | **4.6s** | 反直觉优于卸16（布局/碎片因素待查）· 数据不稳定 |
| 128K · 卸16 · 带 draft | — | **段错误** | `-ot` 正则误伤 draft 权重（无法区分主/次模型同名张量） |
| 256K · 卸32 | — | FAIL(OOM) | |
| 对照：128K 全 GPU | — | OOM | SPRINT-08 已证 |

## 结论

1. **无显著甜点** — 距「损失 <20%」的门槛远（最好 4.6s vs 1.3s = 3.5×）；**默认维持 64K 全 GPU**
2. KV CPU 卸载与 **draft-mtp 冲突**（`-ot` 无法区分主/次模型同名张量；`-otd` 待深查）— 大上下文模式**自动禁用投机**（配置化已内置）
3. 落地形态：`TESS_KV_CPU_LAYERS=N` 可选档（0=默认关闭）— 给「真需要 128K 长上下文且能接受速度损失」的场景留了门

## 使用

```bash
TESS_KV_CPU_LAYERS=16 TESS_CTX=131072 ./onekey_start.sh restart   # 128K 大上下文模式（慢 · 无 mtp）
```

## 复跑要点（实验脚手架教训）

- kill 临时实例必须 `pkill -f "port 8010"` + 轮询 `nvidia-smi compute-apps` 清零 — nohup 直接 kill 外壳会留僵尸实例（曾连坐整轮矩阵）
- `-ot` 在默认 `kv_unified=true` 下无效（KV 是整块 buffer）— 必须配 `--no-kv-unified`
