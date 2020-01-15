#!/bin/bash
trap "exit" INT

echo "###########################################"
echo "##              L2DFMaster               ##"
echo "###########################################"

while true
do
luajit master.lua
echo "L2DFMaster is crashed!"
echo "Rebooting in:"
for i in {3..1}
do
echo "$i..."
done
echo "##########################################"
echo "#      L2DFMaster is restarting now      #"
echo "##########################################"
done