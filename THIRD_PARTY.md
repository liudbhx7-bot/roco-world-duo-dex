# 资料、美术与配音来源

图鉴将资料和媒体随应用打包，以便在离线时扫描精灵、查阅技能和播放介绍。要追溯某个形态，请用应用内的精灵名和形态名查询来源清单。同一游戏编号可以对应多条档案。[逐形态来源清单](RocoDex/Resources/Sources.json)

| 内容 | 1.5 使用的资料和处理方式 |
| --- | --- |
| 精灵档案与系别 | 按 S5 精灵图鉴整理编号、形态、属性和描述，归并不同资料模块。[BWiki 精灵图鉴](https://wiki.biligame.com/nrc/精灵图鉴) · [资料镜像所用版本](https://github.com/JayeGT002/rocom-wiki-data/tree/f98d670c978b3fe3971adbff6af0ec36de9ef81f) |
| 立绘与头像 | 使用各形态的来源图，裁去多余透明区域并为本地识别建立索引。部分形态共用原图；部分早期档案保留此前的整理来源。[逐形态立绘与头像链接](RocoDex/Resources/Sources.json) |
| 特性、技能与进化 | 按形态关联特性、进化分支、自学等级、技能石、血脉和部分传说技能的学习条件。系别、特性和技能卡上使用游戏图标。[BWiki 技能列表](https://wiki.biligame.com/nrc/技能列表) · [随包技能表](RocoDex/Resources/BattleGuide/catalog.json) |
| 生态与分布 | 在 S4「月涌狂想」地图上匹配 S5 精灵资料，保留来源列出的区域、首领和挑战类型。已知区域边界和具体地图标记分别保存。[BWiki 世界地图](https://wiki.biligame.com/nrc/地图) · [随包分布数据与来源](RocoDex/Resources/FieldMaps/Habitats.json) |
| 水蓝蓝动图 | 由项目素材提供者提供，随包保存为循环 APNG。[水蓝蓝动画](RocoDex/Resources/Animations/008.apng) |
| 普通话介绍 | 以 Qwen3-TTS 1.7B CustomVoice 的 Serena 音色，根据每份档案的台词和表演提示预先生成录音，应用播放本地音轨。[Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) · [配音台本](配音台本.csv) |

Wiki 原创文字及其有权授权的资料整理成果按 CC BY-SA 4.0 共享，项目对这些资料的改编沿用同一许可。游戏角色、立绘、图标、地图、相关标识等美术归腾讯及相应权利人所有。引用这些美术用于其他项目时，请单独核对相应权利。仓库源码目前未声明独立的开源许可证。[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
