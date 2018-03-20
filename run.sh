#!/bin/bash

if [ $# == 0 ]; then
  echo "pass file to run"
  echo "ex) ./run.sh src/main.cpp"
  exit 1
fi

if [ $(uname -s) == "Darwin" ]; then
  CURRENT_OS="MACOS"
  # echo "running on macOS"
fi

if [ $(uname -s) == "Linux" ]; then
  CURRENT_OS="LINUX"
fi

INITIALDIR=${PWD} # gives absolute path
# echo "Script executed from: ${INITIALDIR}"

# BASH_SOURCE has the script's path could be absolute, could be relative
SCRIPT_PATH=$(dirname ${BASH_SOURCE[0]})

FIRSTCHAR=${SCRIPT_PATH:0:1}
if [ ${FIRSTCHAR} == "/" ]; then # it's asolute path
  AL_TEMPLATE_PATH=${SCRIPT_PATH}
  AL_LIB_PATH=${AL_TEMPLATE_PATH}/allolib
else # SCRIPT_PATH was relative
  AL_TEMPLATE_PATH=${INITIALDIR}/${SCRIPT_PATH} # make it absolute
  AL_LIB_PATH=${AL_TEMPLATE_PATH}/allolib
fi

# resolve flags
BUILD_TYPE=Release # release build by default
DO_CLEAN=0
IS_VERBOSE=0
VERBOSE_FLAG=OFF

while getopts "dncv" opt; do
  case "${opt}" in
  d)
    BUILD_TYPE=Debug
    POSTFIX=_debug # if release, there's no postfix
    ;;
  n)
    EXIT_AFTER_BUILD=1
    ;;
  c)
    DO_CLEAN=1
    ;;
  v)
    IS_VERBOSE=1
    VERBOSE_FLAG=ON
    ;;
  esac
done
# consume options that were parsed
shift $(expr $OPTIND - 1 )

if [ ${IS_VERBOSE} == 1 ]; then
  echo "BUILD TYPE: ${BUILD_TYPE}"
fi

# build allolib
echo " "
echo "___ building allolib __________"

cd ${AL_LIB_PATH}
git submodule init
git submodule update
if [ ${DO_CLEAN} == 1 ]; then
  if [ ${IS_VERBOSE} == 1 ]; then
    echo "cleaning build"
  fi
  rm -r build
fi
mkdir -p build
cd build
mkdir -p "${BUILD_TYPE}"
cd "${BUILD_TYPE}"
cmake -DCMAKE_BUILD_TYPE=${BUILD_TYPE} -DAL_VERBOSE_OUTPUT=${VERBOSE_FLAG} ../.. > cmake_log.txt
make
LIB_BUILD_RESULT=$?
if [ ${LIB_BUILD_RESULT} != 0 ]; then
  echo "allolib failed to build"
  exit 1 # if lib failed to build, exit
fi

# build gamma if it exists
cd ${AL_TEMPLATE_PATH}
if [ -d "Gamma" ]; then
  echo " "
  echo "___ Gamma found, building Gamma __________"
  cd Gamma
  mkdir -p build
  cd build
  mkdir -p "${BUILD_TYPE}"
  cd "${BUILD_TYPE}"
  cmake ../.. -DCMAKE_BUILD_TYPE=${BUILD_TYPE} > cmake_log.txt
  make
  GAMMA_BUILD_RESULT=$?
  if [ ${GAMMA_BUILD_RESULT} != 0 ]; then
    echo "Gamma failed to build. not linking Gamma"
  else
    GAMMA_INCLUDE_DIRS=${AL_TEMPLATE_PATH}/Gamma # set Gamma linking info if found and built
    if [ BUILD_TYPE == "Release" ]; then
      GAMMA_LINK_LIBS=${AL_TEMPLATE_PATH}/Gamma/lib/libGamma.a
    else
      GAMMA_LINK_LIBS=${AL_TEMPLATE_PATH}/Gamma/lib/libGamma_debug.a
    fi
  fi
fi

# build cuttlebone if it exists
cd ${AL_TEMPLATE_PATH}
if [ -d "cuttlebone" ]; then
  echo " "
  echo "___ cuttlebone found, building cuttlebone __________"
  cd cuttlebone
  mkdir -p build
  cd build
  mkdir -p "${BUILD_TYPE}"
  cd "${BUILD_TYPE}"
  cmake ../.. -DCMAKE_BUILD_TYPE=${BUILD_TYPE} > cmake_log.txt
  make > make_log.txt
  CUTTLEBONE_BUILD_RESULT=$?
  if [ ${CUTTLEBONE_BUILD_RESULT} != 0 ]; then
    echo "cuttlebone failed to build. not linking cuttlebone"
  else
    CUTTLEBONE_INCLUDE_DIRS=${AL_TEMPLATE_PATH}/cuttlebone
    if [ ${CURRENT_OS} == "MACOS" ]; then
      CUTTLEBONE_LINK_LIBS=${AL_TEMPLATE_PATH}/cuttlebone/build/${BUILD_TYPE}/libcuttlebone.dylib
    fi
    if [ ${CURRENT_OS} == "LINUX" ]; then
      CUTTLEBONE_LINK_LIBS=${AL_TEMPLATE_PATH}/cuttlebone/build/${BUILD_TYPE}/libcuttlebone.so
    fi
  fi
fi

# build app

APP_FILE_INPUT="$1" # first argument (assumming we consumed all the options above)
APP_PATH=$(dirname ${APP_FILE_INPUT})
APP_FILE=$(basename ${APP_FILE_INPUT})
APP_NAME=${APP_FILE%.*} # remove extension (once, assuming .cpp)
echo " "
echo "___ building ${APP_NAME} __________"
# echo "    app path: ${APP_PATH}"
# echo "    app file: ${APP_FILE}"
# echo "    app name: ${APP_NAME}"

# echo "${GAMMA_INCLUDE_DIRS}"
# echo "${GAMMA_LINK_LIBS}"

cd ${INITIALDIR}
cd ${APP_PATH}
if [ ${DO_CLEAN} == 1 ]; then
  if [ ${IS_VERBOSE} == 1 ]; then
    echo "cleaning build"
  fi
  rm -r build
fi
mkdir -p build
cd build
mkdir -p ${APP_NAME}
cd ${APP_NAME}
cmake -DCMAKE_BUILD_TYPE=${BUILD_TYPE} -Dal_path=${AL_LIB_PATH} -DAL_APP_FILE=../../${APP_FILE} -Dapp_include_dirs=${GAMMA_INCLUDE_DIRS}\;${CUTTLEBONE_INCLUDE_DIRS}\; -Dapp_link_libs=${GAMMA_LINK_LIBS}\;${CUTTLEBONE_LINK_LIBS}\; -DAL_VERBOSE_OUTPUT=${VERBOSE_FLAG} ${AL_LIB_PATH}/cmake/single_file > cmake_log.txt
make

APP_BUILD_RESULT=$?
if [ ${APP_BUILD_RESULT} != 0 ]; then
  exit 1 # if app failed to build, exit
fi

if [ ${EXIT_AFTER_BUILD} ]; then
  exit 0
fi

# run app
# go to where the binary is so we have cwd there
# (app's cmake is set to put binary in 'bin')
cd ${INITIALDIR}
cd ${APP_PATH}/bin
echo " "
echo "___ running ${APP_NAME} __________"
./"${APP_NAME}${POSTFIX}"