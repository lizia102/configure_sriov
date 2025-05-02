#!/bin/bash

# --- 配置项 ---
# 物理网卡名称将从第一个命令行参数获取
# 要创建的 VF 数量将从第二个命令行参数获取
# 要附加到的虚拟机名称将从第三个（可选）命令行参数获取
VM_NAME=""
# ------------- #

# 检查参数数量
if [ "$#" -lt 2 ]; then
    echo "用法: $0 <physical_interface> <num_vfs> [vm_name]"
    echo "错误：需要至少提供物理接口名称和 VF 数量。"
    exit 1
fi

PHYSICAL_INTERFACE="$1"
NUM_VFS="$2"

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
   echo "错误：此脚本必须以 root 权限运行。" >&2
   exit 1
fi

# 检查物理接口是否存在并确定类型 (Ethernet or InfiniBand)
INTERFACE_TYPE=""
PF_DEVICE_PATH=""
if [ -d "/sys/class/net/${PHYSICAL_INTERFACE}" ]; then
    echo "检测到接口 '$PHYSICAL_INTERFACE' 为以太网类型。"
    INTERFACE_TYPE="net"
    PF_DEVICE_PATH="/sys/class/net/${PHYSICAL_INTERFACE}/device"
elif [ -d "/sys/class/infiniband/${PHYSICAL_INTERFACE}" ]; then
    echo "检测到接口 '$PHYSICAL_INTERFACE' 为 InfiniBand 类型。"
    INTERFACE_TYPE="infiniband"
    PF_DEVICE_PATH="/sys/class/infiniband/${PHYSICAL_INTERFACE}/device"
else
    echo "错误：物理接口 '$PHYSICAL_INTERFACE' 不存在或类型未知。"
    exit 1
fi

# 检查 SR-IOV 是否已启用以及最大 VF 数
SRIOV_TOTALVFS_PATH="${PF_DEVICE_PATH}/sriov_totalvfs"
if [ ! -f "$SRIOV_TOTALVFS_PATH" ]; then
    echo "错误：接口 '$PHYSICAL_INTERFACE' 不支持 SR-IOV 或 SR-IOV 未在 BIOS/UEFI 中启用 (路径: $SRIOV_TOTALVFS_PATH)。"
    exit 1
fi

MAX_VFS=$(cat "$SRIOV_TOTALVFS_PATH")
echo "接口 '$PHYSICAL_INTERFACE' 支持 SR-IOV，最大 VF 数量: $MAX_VFS"

# 检查请求的 VF 数量是否有效
if [ "$NUM_VFS" -le 0 ] || [ "$NUM_VFS" -gt "$MAX_VFS" ]; then
    echo "错误：请求的 VF 数量 ($NUM_VFS) 无效。必须介于 1 和 $MAX_VFS 之间。"
    exit 1
fi

# 配置 VF
SRIOV_NUMVFS_PATH="${PF_DEVICE_PATH}/sriov_numvfs"

# 先尝试将 VF 数量设置为 0，以防已有 VF 配置
echo "正在尝试重置 VF 配置..."
echo 0 > "$SRIOV_NUMVFS_PATH"
sleep 1 # 等待系统响应

CURRENT_VFS=$(cat "$SRIOV_NUMVFS_PATH")
if [ "$CURRENT_VFS" -ne 0 ]; then
    echo "警告：无法将 VF 数量重置为 0。当前 VF 数量: $CURRENT_VFS。继续尝试配置..."
fi

echo "正在为接口 '$PHYSICAL_INTERFACE' 配置 $NUM_VFS 个 VF..."
echo "$NUM_VFS" > "$SRIOV_NUMVFS_PATH"
sleep 1 # 等待系统响应

# 验证配置
CURRENT_VFS=$(cat "$SRIOV_NUMVFS_PATH")
if [ "$CURRENT_VFS" -eq "$NUM_VFS" ]; then
    echo "成功：已为接口 '$PHYSICAL_INTERFACE' 配置 $CURRENT_VFS 个 VF。"
    echo "你可以使用 'ip link show $PHYSICAL_INTERFACE' 查看 VF。"
else
    echo "错误：配置 VF 失败。当前 VF 数量: $CURRENT_VFS，期望数量: $NUM_VFS。"
    exit 1
fi

# --- 将 VF 附加到虚拟机 --- 

# --- 将 VF 附加到虚拟机（可选） --- 

# 检查是否提供了虚拟机名称 (第三个参数)
if [ -z "$3" ]; then
    echo "信息：未提供虚拟机名称，将跳过附加 VF 到虚拟机的步骤。"
else
    VM_NAME="$3"
    echo "准备将 VF 附加到虚拟机 '$VM_NAME'..."

    # 检查 virsh 命令是否存在
    if ! command -v virsh &> /dev/null; then
        echo "错误：未找到 'virsh' 命令。请确保 libvirt-client 已安装。"
        exit 1
    fi

    # 检查虚拟机是否存在且正在运行 (或者至少是定义的)
    if ! virsh dominfo "$VM_NAME" &> /dev/null; then
        echo "错误：虚拟机 '$VM_NAME' 不存在或无法访问。"
        exit 1
    fi

    # 获取物理接口的 PCI 地址，用于查找 VF
    # PF_DEVICE_PATH 已在前面确定
    PF_PCI_ADDR=$(basename $(readlink -f "$PF_DEVICE_PATH"))
    if [ -z "$PF_PCI_ADDR" ]; then
        echo "错误：无法获取物理接口 '$PHYSICAL_INTERFACE' 的 PCI 地址 (路径: $PF_DEVICE_PATH)。"
        exit 1
    fi
    echo "物理接口 '$PHYSICAL_INTERFACE' 的 PCI 地址: $PF_PCI_ADDR"

    ATTACHED_COUNT=0
    FAILED_COUNT=0
    # 循环附加 VF
    for i in $(seq 0 $(($NUM_VFS - 1))); do
        VF_DIR="/sys/bus/pci/devices/${PF_PCI_ADDR}/virtfn${i}"
        if [ -d "$VF_DIR" ]; then
            VF_PCI_ADDR=$(basename $(readlink -f "$VF_DIR"))
            # 将 PCI 地址转换为 libvirt 格式 (0000:41:10.0 -> pci_0000_41_10_0)
            LIBVIRT_PCI_ADDR=$(echo "$VF_PCI_ADDR" | sed 's/:/_/g' | sed 's/\./_/g')
            LIBVIRT_PCI_ADDR="pci_${LIBVIRT_PCI_ADDR}"
            
            echo "找到 VF${i}，PCI 地址: $VF_PCI_ADDR, Libvirt 地址: $LIBVIRT_PCI_ADDR"

            # 创建临时的 libvirt XML 配置文件
            TEMP_XML_FILE="/tmp/vf_attach_${VM_NAME}_${i}.xml"
            cat > "$TEMP_XML_FILE" << EOF
<interface type='hostdev' managed='yes'>
  <source>
    <address type='pci' domain='0x${VF_PCI_ADDR:0:4}' bus='0x${VF_PCI_ADDR:5:2}' slot='0x${VF_PCI_ADDR:8:2}' function='0x${VF_PCI_ADDR:11:1}'/>
  </source>
</interface>
EOF

            echo "正在尝试将 VF${i} ($LIBVIRT_PCI_ADDR) 附加到虚拟机 '$VM_NAME'..."
            if virsh attach-device "$VM_NAME" --file "$TEMP_XML_FILE" --config; then
                echo "成功将 VF${i} 附加到 '$VM_NAME'。"
                ATTACHED_COUNT=$((ATTACHED_COUNT + 1))
            else
                echo "错误：将 VF${i} 附加到 '$VM_NAME' 失败。"
                FAILED_COUNT=$((FAILED_COUNT + 1))
            fi
            # 清理临时文件
            rm -f "$TEMP_XML_FILE"
        else
            echo "警告：未找到 VF${i} 的目录 '$VF_DIR'。跳过附加。"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    done

    echo "--- 附加完成 --- "
    echo "成功附加 $ATTACHED_COUNT 个 VF。"
    echo "失败 $FAILED_COUNT 个 VF。"
    
    if [ $FAILED_COUNT -gt 0 ]; then
        echo "请检查错误信息并确保虚拟机 '$VM_NAME' 已关闭或支持热插拔。"
        # 即使附加失败，VF 创建也可能成功，所以不一定退出 1
        # exit 1
    fi
fi

exit 0