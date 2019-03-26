#!/bin/sh

# Author : Gustavo Guedes
# Date : 21 March 2019
# Contact : gustavoguedesab@gmail.com
# This is a script to automatically install SmartOffice and all of it's components.

BUILD_FOLDER_DIR=~/SMbuild
LISTOFPACKAGES="openjdk-8-jdk git g++ automake make cmake tinyos-tools python python3-pip flex python-requests python-serial python-usb python3-sklearn libmariadbclient-dev gperf bison gcc-msp430 nescc ncc librxtx-java mysql-server python3-mysqldb python-setuptools"

all_pack_installed(){
    PACKAGES_STATUS=$(tail -n 1 "$BUILD_FOLDER_DIR"/install.tool)
    if [ "$PACKAGES_STATUS" != "reboot=done" ]
    then
        echo ""
        echo "Remember to reboot the system."
        echo "reboot=todo" > "$BUILD_FOLDER_DIR"/install.tool
        exit 0
    else
        continue
    fi
}

#reboot status are: done, todo, none
pac_install_build_setup(){
    mkdir -p "$BUILD_FOLDER_DIR"
    cd "$BUILD_FOLDER_DIR"
    REBOOT_NEEDED=$(find -name install.tool)
    if [ "$REBOOT_NEEDED" != "" ] #Found install.log file.
    then
	REBOOT_STATUS=$(tail -n 1 "$REBOOT_NEEDED")
        if [ "$REBOOT_STATUS" = "reboot=done" ]
	then
            echo "Installing Python3 packages."
	    sudo pip3 install pandas
            sudo pip3 install scikit-learn
            sudo pip3 install pymysql
            return 0
        elif [ "$REBOOT_STATUS" = "reboot=todo" ]
        then
            for i in 5 4 3 2 1 0
            do
                sleep 1
                echo "Rebooting system in $i seconds, press Ctrl+C to cancel. (But beware that you must reboot before continuing the installation.)"
            done
            echo "reboot=done" > "$BUILD_FOLDER_DIR"/install.tool
            sudo reboot
        else
            continue
        fi
    else
    	#We will need a reboot ater installing all the packages.
	echo "reboot=none" > "$BUILD_FOLDER_DIR"/install.tool
    fi
    sudo apt -y install $LISTOFPACKAGES
    trap all_pack_installed INT QUIT
    #We should make the rest of the script run automatically after reboot by writing it to init.d, but this shall be done later.
    for i in 5 4 3 2 1 0
    do
        trap all_pack_installed INT QUIT
        sleep 1
        echo "Rebooting system in $i seconds, press Ctrl+C to cancel. (But beware that you must reboot before continuing the installation.)"
    done
    echo "reboot=done" > "$BUILD_FOLDER_DIR"/install.tool
    sudo reboot
    exit 0
}

git_setup(){
    mkdir -p ~/git
    cd ~/git
    TINYOS_REP=$(find -name tinyos-main)
    if [ "$TINYOS_REP" != "" ]
    then
        echo "TinyOS folder already exists."
    else
        git clone --recursive https://github.com/tinyos/tinyos-main.git
    fi

    MANIOT_REP=$(find -name maniot)
    if [ "$MANIOT_REP" != "" ]
    then
        echo "Maniot folder already exists."
    else
        git clone ssh://Git-man-iot@disk/volume1/git/maniot
    fi

    XGBOOST_REP=$(find -name xgboost)
    if [ "$XGBOOST_REP" != "" ]
    then
        echo "XGBOOST folder already exists."
    else
        git clone --recursive --branch release_0.82 https://github.com/dmlc/xgboost.git
    fi
    return 0
}

build_tinyos(){
	sudo ./Bootstrap
    sudo ./configure
    sudo make
    sudo make install
    JNI=$(sudo tos-install-jni)
    if [ "$JNI" != "Installing Java JNI code in /usr/lib/jvm/java-8-openjdk-armhf/lib/arm ... " ]
    then
    	echo "Java Native Interface could not find Java installation, make sure you have installed Java development kit correctrly, reboot your Raspberry and try again."
    else
    	echo "Writing TinyOS initialization script."
    fi
    cd ~/git/tinyos-main
    TINYOS_SH_DIR=$(find -name tinyos.sh)
    if [ "$TINYOS_SH_DIR" != "" ]
    then
    	#It found tinyos.sh so we won't create it all over again.
    	continue
    else
    	echo "export TOSROOT=\"/home/pi/git/tinyos-main\"" > tinyos.sh
        echo "export TOSDIR=\"\$TOSROOT/tos\"" >> tinyos.sh
        echo "export CLASSPATH=\$CLASSPATH:\$TOSROOT/tools/tinyos/java/tinyos.jar:." >> tinyos.sh
        echo "export MAKERULES=\"\$TOSROOT/support/make/Makerules\"" >> tinyos.sh
        echo "export PYTHONPATH=\$PYTHONPATH:\$TOSROOT/tools/tinyos/java/python" >> tinyos.sh
        echo "echo \"setting up TinyOS on source path \$TOSROOT\"" >> tinyos.sh
    fi
    sudo chmod -R 777 ~/git/tinyos-main
    sudo gpasswd -a pi dialout
    TINYOS_BASHRC=$(tail -n 1 /home/pi/.bashrc)
    if [ "$TINYOS_BASHRC" != "source /home/pi/git/tinyos-main/tinyos.sh" ]
    then
    	#Else, we would append to bashrc every single time we run this script.
    	sudo echo "source /home/pi/git/tinyos-main/tinyos.sh" >> /home/pi/.bashrc
    fi
    cd ~/git/tinyos-main
    LIBGETENV=$(find -name libgetenv.so)
    sudo cp $LIBGETENV /usr/bin/
    LIBTOSCOMM=$(find -name libtoscomm.so)
    sudo cp $LIBTOSCOMM /usr/bin/
    return 0
}

tinyos_setup(){
    cd ~/git/tinyos-main/tools

    TINYOS_BUILD=$(find -maxdepth 1 -name config.log)
    if [ "$TINYOS_BUILD" != "" ]
    then
    	echo "TinyOS has already been built, checking if it was correctly built."
    	BUILD_STATUS=$(tail -n 1 "$TINYOS_BUILD")
    	if [ "$BUILD_STATUS" != "configure: exit 0" ]
    	then
    		echo "Something went wrong when building TinyOS last time. Trying again."
    		build_tinyos
    	else
    		echo "TinyOS was built correctly last time."
    	fi
    else
    	echo "TinyOS hasn't been built yet. Building now."
    	build_tinyos
    fi
    return 0
}

xgboost_setup(){
    cd ~/
    echo "import xgboost as xgb" > ~/SMbuild/xgboostver.py
    echo "print (xgb.__version__)" >> ~/SMbuild/xgboostver.py
    XGBOOST_VER=$(python3 ~/SMbuild/xgboostver.py)
    if [ "$XGBOOST_VER" = "0.82" ]
    then
        echo "xgboost is installed."
    else
        echo "xgboost not found, starting compilation."
        cd ~/git
        cd ~/git/xgboost
        mkdir build
        cd build
        cmake ..
        make -j4
        cd ~/git/xgboost/python-package
        sudo python3 setup.py install
    fi
    return 0
}

database_setup(){
    cd ~/git/maniot
    DBSETUP=$(find -name SMDBsetup.sh)
    /bin/bash $DBSETUP
    return 0
}

move_build_folder(){
    MANIOT_FOLDER_DIR=$(find ~/ -name Maniot)
    mv "$BUILD_FOLDER_DIR" "$MANIOT_FOLDER_DIR"
}

read -p "Hello, do you want to install SmartOffice environment and components? (Y/N)" proceed

if [ "$proceed" = N -o "$proceed" = n ]
then
    echo "Ok, see you next time."
    exit 0
else
    echo "Starting installation, this will take a while."
    pac_install_build_setup
    git_setup
    tinyos_setup
    xgboost_setup
    move_build_folder
    database_setup
fi
