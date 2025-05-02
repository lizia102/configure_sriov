# SR-IOV VF 配置与虚拟机绑定工具

## 简介
该脚本用于自动化配置物理网卡的 SR-IOV 虚拟功能（VF）并将其绑定到指定的虚拟机。适用于需要高性能网络虚拟化的场景，如云计算、容器化环境或虚拟化测试。

---

## 安装与依赖
### 硬件要求
1. 支持 SR-IOV 的物理网卡（如 Intel 82599 系列或 Mellanox ConnectX 系列）。
2. BIOS/UEFI 中已启用 SR-IOV 功能。
3. VF 配置需在操作系统内核中启用（通常 Linux 内核默认支持）。

### 软件依赖
1. **libvirt** 及其工具 `virsh`（用于虚拟机管理）：
   ```bash
   sudo apt install libvirt-daemon-system libvirt-clients
   ```
2. **root 权限**：脚本需以管理员权限运行。

---

## 使用方法
### 基本命令格式
```bash
sudo ./configure-sriov-vf.sh <physical_interface> <num_vfs> [vm_name]
```

### 参数说明
| 参数              | 说明                                  | 必需性 |
|-------------------|---------------------------------------|--------|
| `physical_interface` | 物理网卡名称（如 `ens3f0` 或 `eth0`） | 是     |
| `num_vfs`         | 要创建的 VF 数量                      | 是     |
| `vm_name`         | 要附加 VF 的虚拟机名称（可选）        | 否     |

---

## 步骤说明
### 1. 配置 VF
```bash
sudo ./configure-sriov-vf.sh ens3f0 4
```
- 输出示例：
  ```
  检测到接口 'ens3f0' 为以太网类型。
  接口 'ens3f0' 支持 SR-IOV，最大 VF 数量: 6
  正在为接口 'ens3f0' 配置 4 个 VF...
  成功：已为接口 'ens3f0' 配置 4 个 VF。
  ```

### 2. 配置并附加 VF 到虚拟机
```bash
sudo ./configure-sriov-vf.sh ens3f0 2 my_vm
```
- 输出示例：
  ```
  成功：已为接口 'ens3f0' 配置 2 个 VF。
  准备将 VF 附加到虚拟机 'my_vm'...
  成功附加 2 个 VF。
  ```

---

## 功能特性
### 核心功能
1. **自动检测接口类型**：支持以太网和 InfiniBand 接口。
2. **VF 数量校验**：确保请求的 VF 数量在硬件支持范围内。
3. **虚拟机热插拔**：尝试在运行中虚拟机上附加 VF（需支持热插拔）。
4. **错误处理**：
   - 检测 SR-IOV 是否启用
   - 验证虚拟机是否存在
   - 处理 PCI 地址解析失败

---

## 常见问题排查
### 1. 物理接口不支持 SR-IOV
**现象**：
```
错误：接口 'ens3f0' 不支持 SR-IOV 或 SR-IOV 未在 BIOS/UEFI 中启用...
```
**解决方案**：
- 进入 BIOS/UEFI 设置启用 SR-IOV
- 确认网卡型号支持 SR-IOV（通过 `lspci -vvv | grep "Virtualization"` 检查）

### 2. VF 附加到虚拟机失败
**现象**：
```
错误：将 VF0 (0000:82:00.0) 附加到 'my_vm' 失败。
```
**可能原因**：
- 虚拟机未关闭（需关闭后操作）
- libvirt 配置错误
- PCI 地址冲突

**解决方案**：
```bash
# 强制关闭虚拟机
virsh shutdown my_vm
# 检查虚拟机状态
virsh list --all
```

---

## 日志与调试
### 关键日志位置
1. **VF 创建日志**：
   ```bash
   dmesg | grep -i sriov
   ```
2. **虚拟机设备状态**：
   ```bash
   virsh dumpxml <vm_name> | grep -A 5 interface
   ```

### 调试建议
1. 手动验证 VF 存在：
   ```bash
   ip link show | grep vf
   ```
2. 检查 PCI 设备权限：
   ```bash
   ls -l /sys/bus/pci/devices/<PCI_ADDR>
   ```

---


