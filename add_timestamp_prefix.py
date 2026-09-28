# -*- coding: utf-8 -*-
# Relative Path : add_timestamp_prefix.py
# 修改日志：
# 2026-09-25 00:00:00 | 精度收敛 | 时间戳前缀由 YYYYMMDDHHMMSS 收敛为 YYYYMMDDHHMM（不含秒），同步改写文档字符串描述。
import os
import sys
from datetime import datetime

def batch_rename_files(target_dir="D:/"):
    """
    扫描指定目录下所有文件，对【非数字开头】的【文件】增加创建时间前缀 (YYYYMMDDHHMM_)
    保持文件夹名称不动。
    """
    # 统一路径分隔符，防止外部输入的路径带有末尾反斜杠导致后续逻辑拼接故障
    target_dir = target_dir.replace("\\", "/").rstrip("/") + "/"

    if not os.path.exists(target_dir):
        print(f"[错误] 目标路径不存在: {target_dir}")
        return

    print(f"[开始扫描] 目标目录: {target_dir}")
    print("-" * 50)

    success_count = 0
    skip_count = 0
    error_count = 0

    try:
        # 只扫描当前根目录，不进行深度递归，确保逻辑纯净，防止误伤子目录
        for item in os.listdir(target_dir):
            item_path = os.path.join(target_dir, item)

            # 核心边界：如果不是文件（即文件夹），直接跳过
            if not os.path.isfile(item_path):
                continue

            # 原子逻辑1：判断首字符是否已经是数字（防止重复加前缀）
            if item and item[0].isdigit():
                print(f"[跳过] 已存在数字开头: {item}")
                skip_count += 1
                continue

            try:
                # 原子逻辑2：获取文件物理创建时间 (Windows ctime)
                stat = os.stat(item_path)
                created_time = datetime.fromtimestamp(stat.st_ctime)
                prefix = created_time.strftime("%Y%m%d%H%M")
                
                # 标准化组装
                new_item_name = f"{prefix}_{item}"
                new_item_path = os.path.join(target_dir, new_item_name)

                # 执行原子重命名
                os.rename(item_path, new_item_path)
                print(f"[成功] {item} -> {new_item_name}")
                success_count += 1

            except Exception as file_err:
                print(f"[文件操作失败] {item} | 原因: {str(file_err)}")
                error_count += 1

    except Exception as e:
        print(f"[系统级错误] 无法读取目录: {str(e)}")
        return

    print("-" * 50)
    print(f"[执行完毕] 成功: {success_count} | 跳过: {skip_count} | 失败: {error_count}")

if __name__ == "__main__":
    # 默认路径修改为正斜杠，彻底规避语法解析器漏洞
    target_directory = "D:/"
    
    # 支持外部传参覆盖默认路径，例如: python add_timestamp_prefix.py D:\A文件
    if len(sys.argv) > 1:
        target_directory = sys.argv[1]
        
    batch_rename_files(target_directory)