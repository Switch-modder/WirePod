#!/bin/bash

#set -e

ORIGPATH="$(pwd)"

AMD64T="$(pwd)/wire-pod-toolchain/x86_64-unknown-linux-gnu/bin/x86_64-unknown-linux-gnu-"
ARMT="$(pwd)/wire-pod-toolchain/arm-unknown-linux-gnueabihf/bin/arm-unknown-linux-gnueabihf-"
ARM64T="$(pwd)/wire-pod-toolchain/aarch64-linux-gnu/bin/aarch64-linux-gnu-"

DEBCREATEPATH="$(pwd)/debcreate"

# figure out arguments
if [[ $1 == "" ]]; then
    echo "You must provide a version. ex. 1.0.0"
    exit 1
fi

PODVERSION=$1

# gather compilers
if [[ ! -d wire-pod-toolchain ]]; then
    git clone https://github.com/kercre123/wire-pod-toolchain --depth=1
fi

# compile vosk...

function createDEBIAN() {
    ARCH=$1
    mkdir -p ${DEBCREATEPATH}/${ARCH}/DEBIAN
    cp -rfp debfiles/postinst ${DEBCREATEPATH}/${ARCH}/DEBIAN/
    cp -rfp debfiles/preinst ${DEBCREATEPATH}/${ARCH}/DEBIAN/
    chmod 0775 ${DEBCREATEPATH}/${ARCH}/DEBIAN/*
    cd ${DEBCREATEPATH}/${ARCH}/DEBIAN
    echo "Package: wirepod" > control
    echo "Version: $PODVERSION" >> control
    echo "Maintainer: Kerigan Creighton <kerigancreighton@gmail.com>" >> control
    echo "Description: A replacement voice server for the Anki Vector robot." >> control
    echo "Homepage: https://github.com/kercre123/wire-pod" >> control
    echo "Architecture: $ARCH" >> control
    echo "Depends: libopus-dev, libogg-dev, avahi-daemon, libatomic1" >> control
    cd $ORIGPATH
}


function prepareVOSKbuild_AMD64() {
    cd $ORIGPATH
    ARCH=amd64
    mkdir -p build/${ARCH}
    mkdir -p built/${ARCH}
    KALDIROOT="$(pwd)/build/${ARCH}/kaldi"
    BPREFIX="$(pwd)/built/${ARCH}"
    cd build/${ARCH}
    export CC=${AMD64T}gcc
    export CXX=${AMD64T}g++
    export LD=${AMD64T}ld
    export AR=${AMD64T}ar
    export FORTRAN=${AMD64T}gfortran
    export RANLIB=${AMD64T}ranlib
    export AS=${AMD64T}as
    export CPP=${AMD64T}cpp
    export PODHOST=x86_64-unknown-linux-gnu
    if [[ ! -f ${KALDIROOT}/KALDIBUILT ]]; then
        git clone -b vosk --single-branch https://github.com/alphacep/kaldi 
        cd kaldi/tools 
        git clone -b v0.3.20 --single-branch https://github.com/xianyi/OpenBLAS 
        git clone -b v3.2.1  --single-branch https://github.com/alphacep/clapack 
        make -C OpenBLAS ONLY_CBLAS=1 DYNAMIC_ARCH=1 TARGET=NEHALEM USE_LOCKING=1 USE_THREAD=0 all 
        make -C OpenBLAS PREFIX=$(pwd)/OpenBLAS/install install 
        mkdir -p clapack/BUILD && cd clapack/BUILD && cmake .. && make -j 8 && find . -name "*.a" | xargs cp -t ../../OpenBLAS/install/lib 
        cd ${KALDIROOT}/tools
        git clone --single-branch https://github.com/alphacep/openfst openfst 
        cd openfst 
        autoreconf -i 
        CFLAGS="-g -O3" ./configure --prefix=${KALDIROOT}/tools/openfst --host=$PODHOST --enable-static --enable-shared --enable-far --enable-ngram-fsts --enable-lookahead-fsts --with-pic --disable-bin 
        make -j 8 && make install 
        cd ${KALDIROOT}/src 
        ./configure --mathlib=OPENBLAS_CLAPACK --shared --use-cuda=no --host=$PODHOST
        sed -i 's:-msse -msse2:-msse -msse2:g' kaldi.mk 
        sed -i 's: -O1 : -O3 :g' kaldi.mk 
        make -j 8 online2 lm rnnlm 
        touch ${KALDIROOT}/KALDIBUILT
        find ${KALDIROOT} -name "*.o" -exec rm {} \;
    fi
    cd $ORIGPATH
}

function prepareVOSKbuild_ARMARM64() {
    cd $ORIGPATH
    ARCH=$1
    if [[ ${ARCH} == "amd64" ]]; then
        echo "prepareVOSKbuild_ARMARM64: this function is for armhf and arm64 only."
        exit 1
    fi
    mkdir -p build/${ARCH}
    mkdir -p built/${ARCH}
    KALDIROOT="$(pwd)/build/${ARCH}/kaldi"
    BPREFIX="$(pwd)/built/${ARCH}"
    cd build/${ARCH}
    expToolchain ${ARCH}
    if [[ ! -f ${KALDIROOT}/KALDIBUILT ]]; then
        git clone -b vosk --single-branch https://github.com/alphacep/kaldi
        cd kaldi/tools
        git clone -b v0.3.20 --single-branch https://github.com/xianyi/OpenBLAS
        git clone -b v3.2.1  --single-branch https://github.com/alphacep/clapack
        echo ${OPENBLAS_ARGS}
        if [[ $ARCH == "armhf" ]]; then
            make -C OpenBLAS ONLY_CBLAS=1 TARGET=ARMV7 ${OPENBLAS_ARGS} HOSTCC=/usr/bin/gcc USE_LOCKING=1 USE_THREAD=0 all
        elif [[ $ARCH == "arm64" ]] || [[ $ARCH == "aarch64" ]]; then
            make -C OpenBLAS ONLY_CBLAS=1 TARGET=ARMV8 ${OPENBLAS_ARGS} HOSTCC=/usr/bin/gcc USE_LOCKING=1 USE_THREAD=0 all
        fi
        make -C OpenBLAS ${OPENBLAS_ARGS} HOSTCC=gcc USE_LOCKING=1 USE_THREAD=0 PREFIX=$(pwd)/OpenBLAS/install install
        rm -rf clapack/BUILD
        mkdir -p clapack/BUILD && cd clapack/BUILD
        cmake -DCMAKE_C_FLAGS="$ARCHFLAGS" -DCMAKE_C_COMPILER_TARGET=$PODHOST \
            -DCMAKE_C_COMPILER=$CC -DCMAKE_SYSTEM_NAME=Generic -DCMAKE_AR=$AR \
            -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
            -DCMAKE_CROSSCOMPILING=True ..
        make HOSTCC=gcc -j 10 -C F2CLIBS
        make  HOSTCC=gcc -j 10 -C BLAS
        make HOSTCC=gcc  -j 10 -C SRC
        find . -name "*.a" | xargs cp -t ../../OpenBLAS/install/lib
        cd ${KALDIROOT}/tools
        git clone --single-branch https://github.com/alphacep/openfst openfst
        cd openfst
        autoreconf -i
        CFLAGS="-g -O3" ./configure --prefix=${KALDIROOT}/tools/openfst --enable-static --enable-shared --enable-far --enable-ngram-fsts --enable-lookahead-fsts --with-pic --disable-bin --host=${CROSS_TRIPLE} --build=x86-linux-gnu
        make -j 8 && make install
        cd ${KALDIROOT}/src
        sed -i "s:TARGET_ARCH=\"\`uname -m\`\":TARGET_ARCH=$(echo $CROSS_TRIPLE|cut -d - -f 1):g" configure
        sed -i "s: -O1 : -O3 :g" makefiles/linux_openblas_arm.mk
        ./configure --mathlib=OPENBLAS_CLAPACK --shared --use-cuda=no
        make -j 8 online2 lm rnnlm
        find ${KALDIROOT} -name "*.o" -exec rm {} \;
        touch ${KALDIROOT}/KALDIBUILT
    fi
    cd $ORIGPATH
}

function expToolchain() {
    ARCH=$1
    if [[ $ARCH == "amd64" ]]; then
        export CC=${AMD64T}gcc
        export CXX=${AMD64T}g++
        export LD=${AMD64T}ld
        export AR=${AMD64T}ar
        export FC=${AMD64T}gfortran
        export RANLIB=${AMD64T}ranlib
        export AS=${AMD64T}as
        export CPP=${AMD64T}cpp
        export PODHOST=x86_64-unknown-linux-gnu
        export CROSS_TRIPLE=${PODHOST}
        export CROSS_COMPILE=${AMD64T}
        export GOARCH=amd64
    elif [[ $ARCH == "arm64" ]] || [[ $ARCH == "aarch64" ]]; then
        export CC=${ARM64T}gcc
        export CXX=${ARM64T}g++
        export LD=${ARM64T}ld
        export AR=${ARM64T}ar
        export FC=${ARM64T}gfortran
        export RANLIB=${ARM64T}ranlib
        export AS=${ARM64T}as
        export CPP=${ARM64T}cpp
        export PODHOST=aarch64-linux-gnu
        export CROSS_TRIPLE=${PODHOST}
        export CROSS_COMPILE=${ARM64T}
        export GOARCH=arm64
        export GOOS=linux
        export ARCHFLAGS=""
    elif [[ $ARCH == "armhf" ]]; then
        export CC=${ARMT}gcc
        export CXX=${ARMT}g++
        export LD=${ARMT}ld
        export AR=${ARMT}ar
        export FC=${ARMT}gfortran
        export RANLIB=${ARMT}ranlib
        export AS=${ARMT}as
        export CPP=${ARMT}cpp
        export PODHOST=arm-unknown-linux-gnueabihf
        export CROSS_TRIPLE=${PODHOST}
        export CROSS_COMPILE=${ARMT}
        export GOARCH=arm
        export GOARM=7
        export GOOS=linux
        export ARCHFLAGS="-mfloat-abi=hard -mfpu=neon-vfpv4"
    else
        echo "ERROR, Unknown arch: $ARCH"
        exit 1
    fi
}

function doVOSKbuild() {
    ARCH=$1
    cd $ORIGPATH
    KALDIROOT="$(pwd)/build/${ARCH}/kaldi"
    BPREFIX="$(pwd)/built/${ARCH}"
    if [[ ! -f ${BPREFIX}/lib/libvosk.so ]]; then
        cd build/${ARCH}
        expToolchain $ARCH
        if [[ ! -d vosk-api ]]; then
            git clone https://github.com/alphacep/vosk-api --depth=1
        fi
        cd vosk-api/src
        KALDI_ROOT=$KALDIROOT make EXTRA_LDFLAGS="-static-libstdc++" -j8
    fi
    cd "${ORIGPATH}/build/${ARCH}"
    mkdir -p "${BPREFIX}/lib"
    mkdir -p "${BPREFIX}/include"
    cp vosk-api/src/libvosk.so "${BPREFIX}/lib/"
    cp vosk-api/src/vosk_api.h "${BPREFIX}/include/"
    cd $ORIGPATH
}

function buildOPUS() {
    ARCH=$1
    cd $ORIGPATH
    BPREFIX="$(pwd)/built/${ARCH}"
    expToolchain $ARCH
    if [[ ! -f built/${ARCH}/ogg_built ]]; then
        cd build/${ARCH}
        rm -rf ogg
        git clone https://github.com/xiph/ogg --depth=1
        cd ogg
        ./autogen.sh
        ./configure --host=${PODHOST} --prefix=$BPREFIX
        make -j8
        make install
        cd $ORIGPATH
        touch built/${ARCH}/ogg_built
    fi

    if [[ ! -f built/${ARCH}/opus_built ]]; then
        cd build/${ARCH}
        rm -rf opus
        git clone https://github.com/xiph/opus --depth=1
        cd opus
        ./autogen.sh
        ./configure --host=${PODHOST} --prefix=$BPREFIX
        make -j8
        make install
        cd $ORIGPATH
        touch built/${ARCH}/opus_built
    fi
}

function buildWirePod() {
    ARCH=$1
    cd $ORIGPATH

    # get the webroot, intent data, certs
    if [[ ! -d wire-pod ]]; then
        git clone https://github.com/kercre123/wire-pod --depth=1
    fi
    DC=debcreate/${ARCH}
    WPC=wire-pod/chipper
    mkdir -p $DC/etc/wire-pod
    mkdir -p $DC/usr/bin
    mkdir -p $DC/usr/lib
    mkdir -p $DC/usr/include
    mkdir -p $DC/lib/systemd/system
    mkdir -p debcreate/${ARCH}
    cp -rf $WPC/intent-data $DC/etc/wire-pod/
    cp -rf $WPC/epod $DC/etc/wire-pod/
    cp -rf $WPC/webroot $DC/etc/wire-pod/
    cp -rf $WPC/weather-map.json $DC/etc/wire-pod/
    cp -rf built/$ARCH/lib/libvosk.so $DC/usr/lib/
    cp -rf built/$ARCH/include/vosk_api.h $DC/usr/include/
    cp -rf debfiles/wire-pod.service $DC/lib/systemd/system/

    # BUILD WIREPOD
    expToolchain $ARCH

    export CGO_ENABLED=1 
    export CGO_LDFLAGS="-L$(pwd)/built/$ARCH/lib -latomic" 
    export CGO_CFLAGS="-I$(pwd)/built/$ARCH/include"

    go build \
    -tags nolibopusfile \
    -ldflags "-w -s" \
    -o $DC/usr/bin/wire-pod \
    ./pod/main.go ./pod/server.go
}

function finishDeb() {
    ARCH=$1
    mkdir -p $ORIGPATH/final
    cd $ORIGPATH/debcreate
    dpkg-deb -Zxz --build $ARCH
    mv $ARCH.deb ../final/wirepod_$ARCH-$PODVERSION.deb
    cd $ORIGPATH
    echo "final/wirepod_$ARCH-$PODVERSION.deb created successfully"
}

createDEBIAN armhf
createDEBIAN arm64
createDEBIAN amd64

prepareVOSKbuild_AMD64
prepareVOSKbuild_ARMARM64 armhf
prepareVOSKbuild_ARMARM64 arm64

doVOSKbuild amd64
doVOSKbuild armhf
doVOSKbuild arm64

buildOPUS amd64
buildOPUS armhf
buildOPUS arm64

echo "all dependencies complete"

echo "building wire-pod (amd64)..."
buildWirePod amd64
echo "building wire-pod (armhf)..."
buildWirePod armhf
echo "building wire-pod (arm64)..."
buildWirePod arm64

finishDeb amd64
finishDeb armhf
finishDeb arm64