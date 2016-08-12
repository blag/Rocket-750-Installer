#!/bin/bash

printf "Checking that we have enough permissions..."
SCRIPT_USER=$(whoami)
echo "done."

if [[ "${SCRIPT_USER}" != "root" ]]; then
	echo ""
	echo "This script needs root permissions because it may need to install the install the 'dkms' and 'debhelper' packages and will install kernel modules later on."
	echo ""
	echo "Please rerun this script with 'sudo' or as root:"
	echo ""
	echo "    sudo " $(basename $0)
	echo ""
	echo "Exiting."
	exit -2
fi

printf "Checking that dkms is installed..."
dpkg -l dkms >/dev/null; DKMS_PACKAGE_INSTALLED_RESULT=$?
echo "done."

if [[ ${DKMS_PACKAGE_INSTALLED_RESULT} != 0 ]]; then
	printf "The 'dkms' package is not installed and is required for creating and loading kernel modules later on. Attempting to install it..."
	apt install dkms
	if [[ $? != 0 ]]; then
		# Something went wrong
		echo ""
		echo "Unable to install the 'dkms' package."
		echo ""
		echo "Please install it yourself:"
		echo ""
		echo "    sudo apt install dkms"
		echo ""
		echo "and then rerun this script."
		exit -3
	else
		echo "done."
	fi
fi

printf "Checking that debhelper is installed..."
dpkg -l debhelper >/dev/null; DEBHELPER_PACKAGE_INSTALLED_RESULT=$?
echo "done."

if [[ ${DEBHELPER_PACKAGE_INSTALLED_RESULT} != 0 ]]; then
	printf "The 'debhelper' package is not installed and is required for creating DKMS packages later on. Attempting to install it..."
	apt install debhelper
	if [[ $? != 0 ]]; then
		# Something went wrong
		echo ""
		echo "Unable to install the 'debhelper' package."
		echo ""
		echo "Please install it manually:"
		echo ""
		echo "    sudo apt install debhelper"
		echo ""
		echo "and then rerun this script."
		exit -3
	else
		echo "done."
	fi
fi

#TMPDIR=/tmp/R750
TMPDIR=R750

# The URL of the page
DOWNLOAD_PAGE_URL="http://www.highpoint-tech.com/USA_new/r750-Download.htm"

# Get the parts of the URL that we need
DOWNLOAD_DIR_URL=$(dirname ${DOWNLOAD_PAGE_URL})
# Grab the download link
RELATIVE_DOWNLOAD_LINK=$(curl -s ${DOWNLOAD_PAGE_URL} | awk '/Opensource/ { flag=1; next } /FreeBSD Driver/ { flag=0 } flag { print }' | grep href | sed 's|^.*href="\([^"]*\)".*$|\1|')

ABSOLUTE_DOWNLOAD_LINK=$(echo "${DOWNLOAD_DIR_URL}/${RELATIVE_DOWNLOAD_LINK}" | sed 's|[\\/][^\\/]*[\\/]\.\.||g')

printf "Creating temporary directory: '$TMPDIR'..."
mkdir -p "$TMPDIR" 2>/dev/null
echo "done."

printf "Downloading the R750 Open Source Linux driver..."
(cd "$TMPDIR"; curl -s -LO "${ABSOLUTE_DOWNLOAD_LINK}")
echo "done."

printf "Finding the driver tarball..."
R750_TARBALL_NAME=$(find "$TMPDIR" -name "R750*.tar.gz" -exec ls -rt "{}" \; | tail -n 1 | sed "s|^$TMPDIR/||")
echo "done".

printf "Extracting the driver into the temporary directory..."
(cd "$TMPDIR"; tar -xzf "${R750_TARBALL_NAME}")
echo "done."

printf "Finding the official install script..."
R750_BINARY_FILE=$(find "$TMPDIR" -name "r750*.bin" -exec ls -rt "{}" \; | tail -n 1 | sed "s|^$TMPDIR/||")
echo "done."

# From http://stackoverflow.com/a/4025065
vercomp () {
	if [[ $1 == $2 ]]; then
		return 0
	fi

	local IFS=.
	local i ver1=($1) ver2=($2)

	# fill empty fields in ver1 with zeros
	for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
		ver1[i]=0
	done

	for ((i=0; i<${#ver1[@]}; i++)); do
		if [[ -z ${ver2[i]} ]]; then
			# fill empty fields in ver2 with zeros
			ver2[i]=0
		fi

		if ((10#${ver1[i]} > 10#${ver2[i]})); then
			return 1
		fi

		if ((10#${ver1[i]} < 10#${ver2[i]})); then
			return 2
		fi
	done

	return 0
}

testvercomp () {
	vercomp $1 $3
	case $? in
		0)
			op='='
			;;
		1)
			op='>'
			;;
		2)
			op='<'
			;;
	esac

	if [[ $op != $2 ]]; then
		echo "FAIL: Expected '$3', Actual '$op', Arg1 '$1', Arg2 '$2'"
	else
		echo "Pass: '$1 $op $2'"
	fi
}

run_testvercomp () {
	# Run tests
	# argument table format:
	# testarg1   testarg2     expected_relationship
	echo "The following tests should pass"
	while read -r test
	do
		testvercomp $test
	done << EOF
	1            = 1
	2.1          < 2.2
	3.0.4.10     > 3.0.4.2
	4.08         < 4.08.01
	3.2.1.9.8144 > 3.2
	3.2          < 3.2.1.9.8144
	1.2          < 2.1
	2.1          > 1.2
	5.6.7        = 5.6.7
	1.01.1       = 1.1.1
	1.1.1        = 1.01.1
	1            = 1.0
	1.0          = 1
	1.0.2.0      = 1.0.2
	1..0         = 1.0
	1.0          = 1..0
EOF

	echo "The following test should fail (test the tester)"
	testvercomp 1 '>' 1
}

printf "Checking if this Linux kernel is supported..."

# Grab the Linux version of this machine
LINUX_VERSION=$(uname -r | cut -d '-' -f 1)

SUPPORTED_LINUX_VERSION=$(curl -s "${DOWNLOAD_PAGE_URL}" | awk '/Opensource/ { flag=1; next } /FreeBSD Driver/ { flag=0 } flag { print }' | grep Support | sed 's|^.*v\([[:digit:]]*.[[:digit:]]*\).*$|\1|')

if [[ -z "$SUPPORTED_LINUX_VERSION" ]]; then
	echo ""
	echo "Unable to parse Linux version from '${LINUX_VERSION}'"
	echo ""
	echo "Could not determine the supported Linux version. Please contact the developers to update this script." >2
	exit -1
fi

vercomp "${LINUX_VERSION}" "${SUPPORTED_LINUX_VERSION}"; VERSION_CODE=$?

if [[ ${VERSION_CODE} -gt 1 ]]; then
	echo ""
	echo "Found Linux version ${LINUX_VERSION}."
	echo ""
	echo "This Linux kernel version is no longer supported (version comparison: ${VERSION_CODE}). Please upgrade to $SUPPORTED_LINUX_VERSION or later."
	exit -1
fi

echo "done -- it is! Continuing."

printf "Extracting the install files from the binary part of the script..."
OFFSET_COMMAND=$(grep --text ^offset "${TMPDIR}/${R750_BINARY_FILE}" | sed 's|^offset=`\(.*\)`$|\1|' | sed "s|\"\$0\"|${TMPDIR}/${R750_BINARY_FILE}|")

INITIAL_OFFSET=$(eval ${OFFSET_COMMAND})
offset=${INITIAL_OFFSET}

FILESIZES=$(grep --text '^filesizes=' "${TMPDIR}/${R750_BINARY_FILE}" | sed 's|^filesizes="\(.*\)\"$|\1|')

# Copy/pasted (and renamed) from the install script
R_dd() {
	blocks=$(( $3 / 1024 ))
	bytes=$(( $3 % 1024 ))

	dd if="$1" ibs=$2 skip=1 obs=1024 conv=sync 2> /dev/null | \
	{ test $blocks -gt 0 && dd ibs=1024 obs=1024 count=$blocks ; \
	  test $bytes  -gt 0 && dd ibs=1 obs=1024 count=$bytes ; } 2>/dev/null
}

for s in $FILESIZES; do
	(cd "$TMPDIR"; R_dd "${R750_BINARY_FILE}" $offset $s | tar xzf - 2>&1)

	offset=$(( $offset + $s ))
done
echo "done."

# Create the DKMS configuration file
printf "Creating the DKMS configuration file..."
read -r -d '' DKMS_FILE <<EOF
MAKE="make -C $TMPDIR/product/r750/linux KERNELDIR=/lib/modules/${kernelver}/build"
CLEAN="make -C $TMPDIR/product/r750/linux clean"
BUILT_MODULE_NAME=r750
DEST_MODULE_LOCATION=/kernel/drivers/scsi/
BUILT_MODULE_LOCATION=$TMPDIR/product/r750/linux/
PACKAGE_NAME=r750
PACKAGE_VERSION=1.0
AUTOINSTALL=yes
REMAKE_INITRD=yes
EOF

echo "${DKMS_FILE}" > "$TMPDIR/dkms.conf"
echo "done."

printf "Notifying DKMS about the R750 module..."
cp -a "${TMPDIR}" /usr/src/r750-1.0
dkms add -m r750 -v 1.0
echo "done."

printf "Creating a DEB package..."
dkms mkdeb -m r750 -v 1.0 --source-only
echo "done."

