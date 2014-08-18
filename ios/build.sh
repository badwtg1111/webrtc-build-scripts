#!/bin/sh

#  build.sh
#  WebRTC
#
#  Created by Rahul Behera on 6/18/14.
#  Copyright (c) 2014 Pristine, Inc. All rights reserved.

# Get location of the script itself .. thanks SO ! http://stackoverflow.com/a/246128
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
PROJECT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

WEBRTC="$PROJECT_DIR/webrtc"
DEPOT_TOOLS="$PROJECT_DIR/depot_tools"
BUILD="$WEBRTC/libjingle_peerconnection_builds"
function create_directory_if_not_found() {
    if [ ! -d "$1" ];
    then
        mkdir -v "$1"
    fi
}

create_directory_if_not_found "$PROJECT_DIR"
create_directory_if_not_found "$WEBRTC"
create_directory_if_not_found "$WEBRTC/WebRTC"


# Update/Get/Ensure the Gclient Depot Tools
function pull_depot_tools() {

    echo Get the current working directory so we can change directories back when done
    WORKING_DIR=`pwd`
    
    echo If no directory where depot tools should be...
    if [ ! -d "$DEPOT_TOOLS" ]
    then
        echo Make directory for gclient called Depot Tools
        mkdir -p $DEPOT_TOOLS

        echo Pull the depo tools project from chromium source into the depot tools directory
        git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git $DEPOT_TOOLS

    else

        echo Change directory into the depot tools
        cd $DEPOT_TOOLS

        echo Pull the depot tools down to the latest
        git pull
    fi  
    PATH="$PATH:$DEPOT_TOOLS"
    echo Go back to working directory
    cd $WORKING_DIR
}

# Set the base of the GYP defines, instructing gclient runhooks what to generate
function wrbase() {
    export GYP_DEFINES="build_with_libjingle=1 build_with_chromium=0 libjingle_objc=1"
    export GYP_GENERATORS="ninja,xcode"
}

# Add the iOS Device specific defines on top of the base
function wrios() {
    wrbase
    export GYP_DEFINES="$GYP_DEFINES OS=ios target_arch=armv7"
    export GYP_GENERATOR_FLAGS="$GYP_GENERATOR_FLAGS output_dir=out_ios"
    export GYP_CROSSCOMPILE=1
}

# Add the iOS Simulator specific defines on top of the base
function wrsim() {
    wrbase
    export GYP_DEFINES="$GYP_DEFINES OS=ios target_arch=ia32"
    export GYP_GENERATOR_FLAGS="$GYP_GENERATOR_FLAGS output_dir=out_sim"
    export GYP_CROSSCOMPILE=1
}

# Gets the revision number of the current WebRTC svn repo on the filesystem
function get_revision_number() {
    svn info $WEBRTC/trunk | awk '{ if ($1 ~ /Revision/) { print $2 } }'
}

# This funcion allows you to pull the latest changes from WebRTC without doing an entire clone, must faster to build and try changes
# Pass in a revision number as an argument to pull that specific revision ex: update2Revision 6798
function update2Revision() {
    #Ensure that we have gclient added to our environment, so this function can run standalone
    pull_depot_tools 
    cd $WEBRTC

    # Configure gclient to pull from the google code master repo (svn). Git is faster, will be put in a later commit
    gclient config http://webrtc.googlecode.com/svn/trunk
    wrios

    # Make sure that the target os is set to JUST MAC at first by adding that to the .gclient file that gclient config command created
    # Note this is a workaround until one of the depot_tools/ios bugs has been fixed
    echo "target_os = ['mac']" >> .gclient
    if [ -z $1 ]
    then
        sync
    else
        sync "$1"
    fi

    # Delete the last line saying we will only build for mac
    sed -i "" '$d' .gclient

    # Write mac and ios to the target os in the gclient file generated by gclient config
    echo "target_os = ['ios', 'mac']" >> .gclient

    if [ -z $1 ]
        then
        sync
    else
        sync "$1"
    fi

    echo "-- webrtc has been sucessfully updated"
}

# This function cleans out your webrtc directory and does a fresh clone -- slower than a pull
# Pass in a revision number as an argument to clone that specific revision ex: clone 6798
function clone() {

    DIR=`pwd`

    rm -rf $WEBRTC
    mkdir -v $WEBRTC

    update2Revision "$1"
}

# Fire the sync command. Accepts an argument as the revision number that you want to sync to
function sync() {
    pull_depot_tools
    cd $WEBRTC
    if [ -z $1 ]
    then
        gclient sync
    else
        gclient sync -r "$1"
    fi
}

# Convenience function to copy the headers by creating a symbolic link to the headers directory deep within webrtc trunk
function copy_headers() {
    create_directory_if_not_found "$BUILD"
    create_directory_if_not_found "$WEBRTC/headers"
    ln -s $WEBRTC/trunk/talk/app/webrtc/objc/public/ $WEBRTC/headers
}

# Build AppRTC Demo for the simulator (ia32 architecture)
function build_apprtc_sim() {
    cd "$WEBRTC/trunk"

    wrsim
    gclient runhooks

    copy_headers

    WEBRTC_REVISION=`get_revision_number`
    if [ "$WEBRTC_DEBUG" = true ] ; then
        ninja -C "out_sim/Debug-iphonesimulator/" AppRTCDemo
        libtool -static -o "$BUILD/libWebRTC-$WEBRTC_REVISION-sim-Debug.a" $WEBRTC/trunk/out_sim/Debug-iphonesimulator/*.a
    fi

    if [ "$WEBRTC_PROFILE" = true ] ; then
        ninja -C "out_sim/Profile-iphonesimulator/" AppRTCDemo
        libtool -static -o "$BUILD/libWebRTC-$WEBRTC_REVISION-sim-Profile.a" $WEBRTC/trunk/out_sim/Profile-iphonesimulator/*.a
    fi

    if [ "$WEBRTC_RELEASE" = true ] ; then
        ninja -C "out_sim/Release-iphonesimulator/" AppRTCDemo
        libtool -static -o "$BUILD/libWebRTC-$WEBRTC_REVISION-sim-Release.a" $WEBRTC/trunk/out_sim/Release-iphonesimulator/*.a
    fi
}

# Build AppRTC Demo for an armv7 real device
function build_apprtc() {
    cd "$WEBRTC/trunk"
    wrios
    gclient runhooks

    copy_headers

    WEBRTC_REVISION=`get_revision_number`
    if [ "$WEBRTC_DEBUG" = true ] ; then
        ninja -C "out_ios/Debug-iphoneos/" AppRTCDemo
        libtool -static -o "$BUILD/libWebRTC-$WEBRTC_REVISION-ios-Debug.a" $WEBRTC/trunk/out_ios/Debug-iphoneos/*.a
    fi

    if [ "$WEBRTC_PROFILE" = true ] ; then
        ninja -C "out_ios/Profile-iphoneos/" AppRTCDemo
        libtool -static -o "$BUILD/libWebRTC-$WEBRTC_REVISION-ios-Profile.a" $WEBRTC/trunk/out_ios/Profile-iphoneos/*.a
    fi

    if [ "$WEBRTC_RELEASE" = true ] ; then
        ninja -C "out_ios/Release-iphoneos/" AppRTCDemo
        libtool -static -o "$BUILD/libWebRTC-$WEBRTC_REVISION-ios-Release.a" $WEBRTC/trunk/out_ios/Release-iphoneos/*.a
    fi
}


# This function is used to put together the intel (simulator) and armv7 builds (device) into one static library so its easy to deal with in Xcode
# Outputs the file into the build directory with the revision number
function lipo_ia32_and_armv7() {
    WEBRTC_REVISION=`get_revision_number`
    if [ "$WEBRTC_DEBUG" = true ] ; then
        # Lipo the simulator build with the ios build into a universal library
        lipo -create $BUILD/libWebRTC-$WEBRTC_REVISION-sim-Debug.a $BUILD/libWebRTC-$WEBRTC_REVISION-ios-Debug.a -output $BUILD/libWebRTC-$WEBRTC_REVISION-armv7-ia32-Debug.a
        # Delete the latest symbolic link just in case :)
        rm $WEBRTC/libWebRTC-LATEST-Universal-Debug.a
        # Create a symbolic link pointing to the exact revision that is the latest. This way I don't have to change the xcode project file everytime we update the revision number, while still keeping it easy to track which revision you are on
        ln -s $BUILD/libWebRTC-$WEBRTC_REVISION-armv7-ia32-Debug.a $WEBRTC/libWebRTC-LATEST-Universal-Debug.a
        # Make it clear which revision you are using .... You don't want to get in the state where you don't know which revision you were using... trust me
        echo "The libWebRTC-LATEST-Universal-Debug.a in this same directory, is revision " > $WEBRTC/libWebRTC-LATEST-Universal-Debug.a.version.txt
        # Also write to a file for funzies
        echo $WEBRTC_REVISION >> $WEBRTC/libWebRTC-LATEST-Universal-Debug.a.version.txt
    fi

    if [ "$WEBRTC_PROFILE" = true ] ; then
        lipo -create $BUILD/libWebRTC-$WEBRTC_REVISION-sim-Profile.a $BUILD/libWebRTC-$WEBRTC_REVISION-ios-Profile.a -output $BUILD/libWebRTC-$WEBRTC_REVISION-armv7-ia32-Profile.a
        rm $WEBRTC/libWebRTC-LATEST-Universal-Profile.a
        ln -s $BUILD/libWebRTC-$WEBRTC_REVISION-armv7-ia32-Profile.a $WEBRTC/libWebRTC-LATEST-Universal-Profile.a
        echo "The libWebRTC-LATEST-Universal-Profile.a in this same directory, is revision " > $WEBRTC/libWebRTC-LATEST-Universal-Profile.a.version.txt
        echo $WEBRTC_REVISION >> $WEBRTC/libWebRTC-LATEST-Universal-Profile.a.version.txt
    fi

    if [ "$WEBRTC_RELEASE" = true ] ; then
        lipo -create $BUILD/libWebRTC-$WEBRTC_REVISION-sim-Release.a $BUILD/libWebRTC-$WEBRTC_REVISION-ios-Release.a -output $BUILD/libWebRTC-$WEBRTC_REVISION-armv7-ia32-Release.a
        rm $WEBRTC/libWebRTC-LATEST-Universal-Release.a
        ln -s $BUILD/libWebRTC-$WEBRTC_REVISION-armv7-ia32-Release.a $WEBRTC/libWebRTC-LATEST-Universal-Release.a
        echo "The libWebRTC-LATEST-Universal-Release.a in this same directory, is revision " > $WEBRTC/libWebRTC-LATEST-Universal-Release.a.version.txt
        echo $WEBRTC_REVISION >> $WEBRTC/libWebRTC-LATEST-Universal-Release.a.version.txt
    fi

}


# Convenience method to just "get webrtc" -- a clone
# Pass in an argument if you want to get a specific webrtc revision
function get_webrtc() {
    pull_depot_tools
    clone "$1"
}

# Build webrtc for an ios device and simulator, then create a universal library
function build_webrtc() {
    pull_depot_tools
    build_apprtc
    build_apprtc_sim
    lipo_ia32_and_armv7
}


# Get webrtc then build webrtc
function dance() {
    # These next if statement trickery is so that if you run from the command line and don't set anything to build, it will default to the debug profile.
    BUILD_DEBUG=true
    if [ "$WEBRTC_RELEASE" = true ] ; then
        BUILD_DEBUG=false
    fi
    if [ "$WEBRTC_PROFILE" = true ] ; then
        BUILD_DEBUG=false
    fi

    if [ "$BUILD_DEBUG" = true ] ; then
        WEBRTC_DEBUG=true
    fi


    get_webrtc
    build_webrtc
    echo "Finished Dancing!"
}
