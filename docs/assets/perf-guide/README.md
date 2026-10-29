# 配图目录说明

本目录存放《医院月度绩效核算与人员管理操作指南》的界面截图。

## 目录约定

```
docs/
├── 医院月度绩效核算与人员管理操作指南.md
└── assets/
    └── perf-guide/
        ├── README.md          ← 本文件（图片清单）
        ├── 01-staff-add.png
        ├── 02-...
        └── ...
```

- 文档与 `assets/` 是**同级目录**，正文里的图片路径统一写成 `assets/perf-guide/xx.png`（相对路径）。
- 文件名**只用小写英文、数字和短横线**，不要中文、不要空格，避免导出 Word/PDF 时路径失效。
- 截图统一用 `.png`。

## 命名清单（按文档出现顺序）

| 序号 | 文件名 | 截图内容 | 所在章节 |
|---|---|---|---|
| 1 | `01-staff-add.png` | 员工管理-新增员工弹窗（含「人员编码」） | 1.4.1 |
| 2 | `02-user-reset-password.png` | 用户管理列表（「更多 → 重置密码」） | 1.4.2 |
| 3 | `03-avatar-change-password.png` | 右上角头像菜单（「修改密码」） | 1.4.2 |
| 4 | `04-role-edit.png` | 角色管理-编辑弹窗（权限 / 用户） | 1.4.3 |
| 5 | `05-raw-data-list.png` | 原始数据列表（拉取状态列） | 2.1 |
| 6 | `06-local-import-tab.png` | 原始数据-本地文件导入页签 | 2.2 |
| 7 | `07-maintain-detail-buttons.png` | 维护表详情页（右上角按钮区） | 2.2 |
| 8 | `08-reward-edit.png` | 综合奖惩明细新增 / 编辑页 | 2.2 |
| 9 | `09-staff-code-mapping.png` | 员工工号对照表 | 2.2 |
| 10 | `10-offline-workload.png` | 线下工作量明细表 | 2.2 |
| 11 | `11-special-incentive.png` | 专项激励配置表 | 2.2 |
| 12 | `12-post-coefficient.png` | 科室岗位系数月度明细表 | 2.2 |
| 13 | `13-calendar.png` | 绩效核算日历维度表 | 2.2 |
| 14 | `14-tcm-disease.png` | 中医优势病种入组患者明细表 | 2.2 |
| 15 | `15-rvu-version.png` | 医院收费项目绩效点数版本维表 | 2.2 |
| 16 | `16-generate-list.png` | 科室核算表生成列表 | 2.3 |
| 17 | `17-generate-detail.png` | 核算表详情页（下发按钮 / 是否下发） | 2.3 |
| 18 | `18-result-modal.png` | 结果值明细弹窗（计算过程 / 明细 JSON） | 2.3 |
| 19 | `19-confirm-list.png` | 科室核算表确认列表 | 2.4 |
| 20 | `20-confirm-detail.png` | 核算表确认详情（确认 / 撤回 / 期间结账） | 2.4 |
| 21 | `21-dept-manager.png` | 基础服务 / 科室管理（负责人列） | 2.4 |
| 22 | `22-filling-list.png` | 二次分配额度填报列表 | 2.5 |
| 23 | `23-filling-drawer-draft.png` | 填报抽屉-草稿态 | 2.5 |
| 24 | `24-filling-drawer-submitted.png` | 填报抽屉-已提交态 | 2.5 |
| 25 | `25-analysis-detail.png` | 科室绩效明细分析 | 2.6.1 |
| 26 | `26-analysis-trend.png` | 近 6 个月趋势弹窗 | 2.6.1 |
| 27 | `27-analysis-settlement.png` | 科室结算总额分析 | 2.6.2 |
| 28 | `28-analysis-secondary.png` | 二次分配结算分析 | 2.6.3 |

## MarkText 使用建议

1. `文件 → 打开文件夹`，选择 `docs` 目录，再打开里面的 `.md`，这样相对路径最稳。
2. 插入图片：`Ctrl + Shift + I`（或菜单 `段落 → 图片`），选择 `assets/perf-guide/` 下对应文件。
3. 在 `首选项 → 图片` 中把「复制图片到文件夹」设为 `assets/perf-guide`，避免写成绝对路径。
4. 截图直接按上表文件名保存到 `assets/perf-guide/`，文档里的链接已经写好，不用再改正文。
5. 检查：在 MarkText 里图片能正常显示、导出 PDF 后图片仍在，即完成。
