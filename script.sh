#/bin/bash

# Definir variables

imagen_base="bullseye-base.qcow2"
imagen_final="maquina1.qcow2"
imagen_nueva="newmaquina1.qcow2"
nmaquina="maquina1"
os="debian10"
index=index.j2
www=/var/www/html/  

echo "Creando la imagen"
qemu-img create -f qcow2 -b $imagen_base $imagen_final 5G > /dev/null 2>&1
cp maquina1.qcow2 newmaquina1.qcow2 
virt-resize --expand /dev/sda1 maquina1.qcow2 newmaquina1.qcow2 > /dev/null 2>&1
mv newmaquina1.qcow2 maquina1.qcow2
sleep 3
clear

echo "Creando red "
echo "<network>
  <name>intra</name>
  <bridge name='virbr12'/>
  <forward/>
  <ip address='10.10.20.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.10.20.2' end='10.10.20.254'/>
    </dhcp>
  </ip>
</network>" > intra.xml
sleep 1
sleep 1
virsh -c qemu:///system net-define intra.xml > /dev/null 2>&1     
virsh -c qemu:///system net-start intra  > /dev/null 2>&1
virsh -c qemu:///system net-autostart intra > /dev/null 2>&1 
echo "Red interna creada e iniciada"
sleep 3
clear
echo "Creando maquina virtual"
virt-install --connect qemu:///system --name $nmaquina --ram 1024 --vcpus 1 --disk $imagen_final --network network=intra --network network=default --os-type linux --os-variant debian10 --import --noautoconsole
sleep 8
virsh -c qemu:///system start $nmaquina > /dev/null 2>&1
virsh -c quemu///system autostart $nmaquina > /dev/null 2>&1
echo "Iniciando la máquina $nmaquina" 
clear

sleep 10
ip=$(virsh -c qemu:///system domifaddr maquina1 | grep -oE "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n 1) 

echo "Pasando clave pública a la máquina virtual"
ssh-copy-id debian@$ip
sleep 5

virsh -c qemu:///system vol-create-as --name maquina1-raw.img --capacity 1G --format raw --pool default > /dev/null 2>&1 
echo "Conectando el nuevo volumen a la máquina"
virsh -c qemu:///system attach-disk maquina1 /var/lib/libvirt/images/maquina1-raw.img vdb --targetbus virtio --persistent > /dev/null 2>&1
echo "Creando sistema de ficheros XFS"
ssh debian@$ip sudo apt update -y > /dev/null 2>&1
ssh debian@$ip sudo apt install xfsprogs -y > /dev/null 2>&1
ssh debian@$ip sudo modprobe -V xfs > /dev/null 2>&1
ssh debian@$ip sudo mkfs.xfs /dev/vdb > /dev/null 2>&1
echo "Montando volumen en /var/www/html"
ssh debian@$ip sudo mkdir /var/www 
ssh debian@$ip sudo mkdir /var/www/html 
ssh debian@$ip sudo mount /dev/vdb /var/www/html
sleep 5
ssh debian@$ip "sudo -- bash -c 'echo "/dev/vdb /var/www/html xfs defaults 0 0" >> /etc/fstab'"
sleep 2
clear


echo "Instalando apache2 y copiando index"
ssh debian@$ip sudo apt install apache2 -y > /dev/null 2>&1
scp index.j2 debian@$ip:/home/debian > /dev/null 2>&1
ssh debian@$ip sudo mv /home/debian/index.j2 /var/www/html/index.j2 > /dev/null 2>&1 
sleep 4
ssh debian@$ip sudo rm /var/www/html/index.html > /dev/null 2>&1
ssh debian@$ip sudo mv /var/www/html/index.j2 /var/www/html/index.html > /dev/null 2>&1 
sleep 1
clear
echo "La dirección IP de la máquina es $ip"
echo "Pulsa una tecla para continuar"
read

echo "Instalando LXC y el container1"
ssh debian@$ip sudo apt install lxc -y > /dev/null 2>&1
ssh debian@$ip sudo lxc-create -t download -n container1 -- -d debian -r buster -a amd64 > /dev/null 2>&1 
sleep 5
clear

echo "Añadiendo interfaz bridge a la máquina virtual y configurándola"
virsh -c qemu:///system shutdown $nmaquina > /dev/null 2>&1
sleep 10
virsh -c qemu:///system attach-interface $nmaquina bridge br0 --model virtio  --config  
virsh -c qemu:///system start $nmaquina > /dev/null 2>&1
sleep 20
ssh debian@$ip "sudo -- bash -c 'echo "allow-hotplug enp9s0" >> /etc/network/interfaces && echo "iface enp9s0 inet dhcp" >> /etc/network/interfaces'"
sleep 3
ssh debian@$ip sudo dhclient -r && dhclient
sleep 8
clear

echo "La nueva IP de la máquina es:"

virsh -c qemu:///system domifaddr $nmaquina
sleep 5
echo "Apagando la máquina y aumentando la RAM "
virsh -c qemu:///system shutdown $nmaquina > /dev/null 2>&1
sleep 5
virt-xml -c qemu:///system  $nmaquina --edit --memory memory=2048,currentMemory=2048
echo "Iniciando la máquina y creando la snapshot"
virsh -c qemu:///system start $nmaquina > /dev/null 2>&1
sleep 5
clear
virsh -c qemu:///system snapshot-create-as $nmaquina --name "snapshot1" --description "Snapshot_máquina" --disk-only --atomic
echo "Fin del script"


