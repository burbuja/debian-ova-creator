#!/bin/bash

debver=""
debarch="amd64"

show_help() {
    cat << EOF
Usage: $0 [options]

Options:
  -d <debian_version>  Specify Debian version (required).
                       Supported: "11", "12", "13", "bullseye", "bookworm",
                       "trixie", "sid"
  -h                   Show this help message

Examples:
  $0 -d bullseye
  $0 -d 12
  $0 -d trixie
  $0 -d sid
EOF
}

while getopts ":d:h" opt; do
    case "$opt" in
        d)
            debver="$OPTARG"
            ;;
        h)
            show_help
            exit 0
            ;;
        :)
            echo "Error: Option -$OPTARG requires an argument." >&2
            show_help
            exit 1
            ;;
        \?)
            echo "Error: Invalid option -$OPTARG" >&2
            show_help
            exit 1
            ;;
    esac
done

if [[ -z "$debver" ]]; then
    echo "Error: Debian version is required (-d)" >&2
    show_help
    exit 1
fi

case "$debver" in
    11|bullseye)
        debver="11"
        debcodename="bullseye"
        ;;
    12|bookworm)
        debver="12"
        debcodename="bookworm"
        ;;
    13|trixie)
        debver="13"
        debcodename="trixie"
        ;;
    sid)
        debver="sid"
        debcodename="sid/daily"
        debarch="amd64-daily"
        ;;
    *)
        echo "Error: Unsupported version $debver" >&2
        show_help
        exit 1
        ;;
esac

DEBIAN_VERSION=${debver}
DEBIAN_NAME=${debcodename}
DEBIAN_ARCH=${debarch}

# More information:
# - https://knowledge.broadcom.com/external/article/315655/virtual-machine-hardware-versions.html
VIRTUAL_SYSTEM_TYPE=vmx-19

FILE_NAME=debian-$DEBIAN_VERSION-genericcloud-$DEBIAN_ARCH
FILE_ORIG_EXT=qcow2
FILE_DEST_EXT=vmdk
FILE_SIGN_EXT=mf
FILE_ORIG_URL=https://cdimage.debian.org/images/cloud/$DEBIAN_NAME/latest/$FILE_NAME.$FILE_ORIG_EXT
# FILE_ORIG_URL=https://cloud.debian.org/images/cloud/$DEBIAN_NAME/latest/$FILE_NAME.$FILE_ORIG_EXT


# More information:
# - https://github.com/vmware/open-vm-tools/blob/master/open-vm-tools/lib/include/guest_os_tables.h
# - https://github.com/vmware/pyvmomi/blob/master/pyVmomi/vim/vm/GuestOsDescriptor.pyi
# - https://abiquo.atlassian.net/wiki/spaces/doc/pages/311377588/Guest+operating+system+definition+for+VMware
OVF_OS_ID=96
OVF_OS_TYPE=debian11_64Guest

CURRENT_DATE=$(date +%Y%m%d)

# You'll need the wget package
if [ ! -f "$FILE_NAME.$FILE_ORIG_EXT" ]; then
    wget "$FILE_ORIG_URL"
else
    echo "The file $FILE_NAME.$FILE_ORIG_EXT was already downloaded"
fi

# You'll need the qemu-img package
if [ ! -f "$FILE_NAME.$FILE_DEST_EXT" ]; then
    qemu-img convert -f $FILE_ORIG_EXT -O $FILE_DEST_EXT -o subformat=streamOptimized "$FILE_NAME.$FILE_ORIG_EXT" "$FILE_NAME.$FILE_DEST_EXT"
else
    echo "The file $FILE_NAME.$FILE_DEST_EXT was already created"
fi

FILE_DEST_SIZE=$(wc -c "$FILE_NAME.$FILE_DEST_EXT" | cut -d " " -f1)

cat <<EOF | tee "$FILE_NAME.ovf" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://schemas.dmtf.org/ovf/envelope/1" xmlns:cim="http://schemas.dmtf.org/wbem/wscim/1/common" xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1" xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData" xmlns:vmw="http://www.vmware.com/schema/ovf" xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <References>
    <File ovf:href="$FILE_NAME.$FILE_DEST_EXT" ovf:id="file1" ovf:size="$FILE_DEST_SIZE"/>
  </References>
  <DiskSection>
    <Info>Virtual disk information</Info>
    <Disk ovf:capacity="10737418240" ovf:capacityAllocationUnits="byte" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" ovf:populatedSize="0"/>
  </DiskSection>
  <NetworkSection>
    <Info>The list of logical networks</Info>
    <Network ovf:name="VM Network">
      <Description>The VM Network network</Description>
    </Network>
  </NetworkSection>
  <VirtualSystem ovf:id="$FILE_NAME-$CURRENT_DATE">
    <Info>A virtual machine</Info>
    <Name>$FILE_NAME-$CURRENT_DATE</Name>
    <OperatingSystemSection ovf:id="$OVF_OS_ID" vmw:osType="$OVF_OS_TYPE">
      <Info>The kind of installed guest operating system</Info>
      <Description>Debian GNU/Linux $DEBIAN_VERSION (64-bit)</Description>
    </OperatingSystemSection>

    <ProductSection ovf:required="false">
      <Info>Cloud-Init customization</Info>
      <Product>Debian GNU/Linux $DEBIAN_VERSION ($CURRENT_DATE)</Product>
      <Property ovf:key="instance-id" ovf:type="string" ovf:userConfigurable="true" ovf:value="id-ovf">
          <Label>A Unique Instance ID for this instance</Label>
          <Description>Specifies the instance id.  This is required and used to determine if the machine should take "first boot" actions</Description>
      </Property>
      <Property ovf:key="hostname" ovf:type="string" ovf:userConfigurable="true" ovf:value="debianguest">
          <Description>Specifies the hostname for the appliance</Description>
      </Property>
      <Property ovf:key="seedfrom" ovf:type="string" ovf:userConfigurable="true">
          <Label>Url to seed instance data from</Label>
          <Description>This field is optional, but indicates that the instance should 'seed' user-data and meta-data from the given url.  If set to 'http://tinyurl.com/sm-' is given, meta-data will be pulled from http://tinyurl.com/sm-meta-data and user-data from http://tinyurl.com/sm-user-data.  Leave this empty if you do not want to seed from a url.</Description>
      </Property>
      <Property ovf:key="public-keys" ovf:type="string" ovf:userConfigurable="true" ovf:value="">
          <Label>ssh public keys</Label>
          <Description>This field is optional, but indicates that the instance should populate the default user's 'authorized_keys' with this value</Description>
      </Property>
      <Property ovf:key="user-data" ovf:type="string" ovf:userConfigurable="true" ovf:value="">
          <Label>Encoded user-data</Label>
          <Description>In order to fit into a xml attribute, this value is base64 encoded . It will be decoded, and then processed normally as user-data.</Description>
          <!--  The following represents '#!/bin/sh\necho "hi world"'
          ovf:value="IyEvYmluL3NoCmVjaG8gImhpIHdvcmxkIgo="
        -->
      </Property>
      <Property ovf:key="password" ovf:type="string" ovf:userConfigurable="true" ovf:value="">
          <Label>Default User's password</Label>
          <Description>If set, the default user's password will be set to this value to allow password based login.  The password will be good for only a single login.  If set to the string 'RANDOM' then a random password will be generated, and written to the console.</Description>
      </Property>
    </ProductSection>

    <VirtualHardwareSection ovf:transport="iso">
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemIdentifier>$FILE_NAME-$CURRENT_DATE</vssd:VirtualSystemIdentifier>
        <vssd:VirtualSystemType>$VIRTUAL_SYSTEM_TYPE</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
        <rasd:Description>Number of Virtual CPUs</rasd:Description>
        <rasd:ElementName>2 virtual CPU(s)</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>2</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:ElementName>1024MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>1024</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Description>SCSI Controller</rasd:Description>
        <rasd:ElementName>SCSI Controller 0</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>VirtualSCSI</rasd:ResourceSubType>
        <rasd:ResourceType>6</rasd:ResourceType>
      </Item>
      <Item ovf:required="false">
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:ElementName>serial0</rasd:ElementName>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:ResourceSubType>vmware.serialport.device</rasd:ResourceSubType>
        <rasd:ResourceType>21</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="yieldOnPoll" vmw:value="false" />
      </Item>
      <Item>
        <rasd:Address>1</rasd:Address>
        <rasd:Description>IDE Controller</rasd:Description>
        <rasd:ElementName>VirtualIDEController 1</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceType>5</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Description>IDE Controller</rasd:Description>
        <rasd:ElementName>VirtualIDEController 0</rasd:ElementName>
        <rasd:InstanceID>6</rasd:InstanceID>
        <rasd:ResourceType>5</rasd:ResourceType>
      </Item>
      <Item ovf:required="false">
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:ElementName>VirtualVideoCard</rasd:ElementName>
        <rasd:InstanceID>7</rasd:InstanceID>
        <rasd:ResourceType>24</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="enable3DSupport" vmw:value="false"/>
        <vmw:Config ovf:required="false" vmw:key="enableMPTSupport" vmw:value="false"/>
        <vmw:Config ovf:required="false" vmw:key="use3dRenderer" vmw:value="automatic"/>
        <vmw:Config ovf:required="false" vmw:key="useAutoDetect" vmw:value="false"/>
        <vmw:Config ovf:required="false" vmw:key="videoRamSizeInKB" vmw:value="4096"/>
      </Item>
      <Item ovf:required="false">
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:ElementName>VirtualVMCIDevice</rasd:ElementName>
        <rasd:InstanceID>8</rasd:InstanceID>
        <rasd:ResourceSubType>vmware.vmci</rasd:ResourceSubType>
        <rasd:ResourceType>1</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="allowUnrestrictedCommunication" vmw:value="false"/>
      </Item>
      <Item ovf:required="false">
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:ElementName>CD-ROM 1</rasd:ElementName>
        <rasd:InstanceID>9</rasd:InstanceID>
        <rasd:Parent>5</rasd:Parent>
        <rasd:ResourceSubType>vmware.cdrom.remotepassthrough</rasd:ResourceSubType>
        <rasd:ResourceType>15</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="backing.exclusive" vmw:value="false"/>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:ElementName>Hard Disk 1</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>10</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="backing.writeThrough" vmw:value="false"/>
      </Item>
      <Item ovf:required="false">
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:Description>Floppy Drive</rasd:Description>
        <rasd:ElementName>Floppy 1</rasd:ElementName>
        <rasd:InstanceID>11</rasd:InstanceID>
        <rasd:ResourceSubType>vmware.floppy.remotedevice</rasd:ResourceSubType>
        <rasd:ResourceType>14</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>7</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Connection>VM Network</rasd:Connection>
        <rasd:Description>VmxNet3 ethernet adapter on &quot;VM Network&quot;</rasd:Description>
        <rasd:ElementName>Ethernet 1</rasd:ElementName>
        <rasd:InstanceID>12</rasd:InstanceID>
        <rasd:ResourceSubType>VmxNet3</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="wakeOnLanEnabled" vmw:value="true"/>
      </Item>
      <vmw:Config ovf:required="false" vmw:key="cpuHotAddEnabled" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="cpuHotRemoveEnabled" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="firmware" vmw:value="bios"/>
      <vmw:Config ovf:required="false" vmw:key="virtualICH7MPresent" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="virtualSMCPresent" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="memoryHotAddEnabled" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="nestedHVEnabled" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="powerOpInfo.powerOffType" vmw:value="preset"/>
      <vmw:Config ovf:required="false" vmw:key="powerOpInfo.resetType" vmw:value="preset"/>
      <vmw:Config ovf:required="false" vmw:key="powerOpInfo.standbyAction" vmw:value="checkpoint"/>
      <vmw:Config ovf:required="false" vmw:key="powerOpInfo.suspendType" vmw:value="preset"/>
      <vmw:Config ovf:required="false" vmw:key="tools.afterPowerOn" vmw:value="true"/>
      <vmw:Config ovf:required="false" vmw:key="tools.afterResume" vmw:value="true"/>
      <vmw:Config ovf:required="false" vmw:key="tools.beforeGuestShutdown" vmw:value="true"/>
      <vmw:Config ovf:required="false" vmw:key="tools.beforeGuestStandby" vmw:value="true"/>
      <vmw:Config ovf:required="false" vmw:key="tools.syncTimeWithHost" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="tools.toolsUpgradePolicy" vmw:value="manual"/>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
EOF

FILE_DEST_SUM=$(sha256sum "$FILE_NAME.$FILE_DEST_EXT" | cut -d " " -f1)
FILE_OVF_SUM=$(sha256sum "$FILE_NAME.ovf" | cut -d " " -f1)

cat <<EOF | tee "$FILE_NAME.$FILE_SIGN_EXT" > /dev/null
SHA256($FILE_NAME.$FILE_DEST_EXT)= $FILE_DEST_SUM
SHA256($FILE_NAME.ovf)= $FILE_OVF_SUM
EOF

tar -vcf "$FILE_NAME.ova" \
         "$FILE_NAME.ovf" \
         "$FILE_NAME.$FILE_SIGN_EXT" \
         "$FILE_NAME.$FILE_DEST_EXT"
