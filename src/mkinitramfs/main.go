package main

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"

	flags "github.com/spf13/pflag"

	"github.com/greeneg/AssimilatorOS/src/mkinitramfs/config"
	earlyfirmware "github.com/greeneg/AssimilatorOS/src/mkinitramfs/earlyFirmware"
	"github.com/greeneg/AssimilatorOS/src/mkinitramfs/initramfs"
)

const defaultPlugins = "busybox, busybox-init, kernel-modules, mdev, mdev-rules, fs, compression"
const VERSION = "mkinitramfs 0.0.2"

type enum struct {
	Allowed []string
	Value   string
}

func newEnum(allowed []string, d string) *enum {
	return &enum{
		Allowed: allowed,
		Value:   d,
	}
}

func (a enum) String() string {
	return a.Value
}

func (a *enum) Set(p string) error {
	isIncluded := func(opts []string, val string) bool {
		for _, opt := range opts {
			if val == opt {
				return true
			}
		}
		return false
	}
	if !isIncluded(a.Allowed, p) {
		return fmt.Errorf("%s is not included in %s", p, strings.Join(a.Allowed, ","))
	}
	a.Value = p
	return nil
}

func (a *enum) Type() string {
	return "string"
}

func charsToString(ca []int8) string {
	s := make([]byte, len(ca))
	var lens int
	for ; lens < len(ca); lens++ {
		if ca[lens] == 0 {
			break
		}
		s[lens] = uint8(ca[lens])
	}
	return string(s[0:lens])
}

func processFlags(kRelease string, defKModDir string, config config.Config) config.Config {
	// Set our allowed compression types
	compressor := newEnum([]string{"bzip2", "gzip", "lzma", "lzo", "xz"}, "xz")

	// Command line flags
	configFile := flags.StringP("config-file", "C", "/etc/mkinitramfs/config.json", "Default location of the JSON configuration of the tool")
	kver := flags.StringP("kernel-version", "k", kRelease, "Use the specified version of the kernel to create the initramfs")
	kmodDir := flags.StringP("kernel-module-dir", "K", defKModDir, "Use the specified directory for the kernel modules to include")
	useForce := flags.BoolP("force", "f", false, "Overwrite the existing initramfs file")
	stripBinaries := flags.BoolP("strip", "s", false, "Strip installed binaries")
	file := flags.StringP("file", "F", "/boot/initramfs.img", "Filename to write")
	plugins := flags.StringArrayP("plugins", "p", config.Modules, "Plugins to enable for the build")
	tmpDir := flags.StringP("tempdir", "t", "", "Temporary directory to use for creating the initramfs")
	earlyFirmwareTmpDir := flags.StringP("early-fw-tmpdir", "e", "", "Temporary directory for creating the early firmware archive")
	enableEarlyMicrocode := flags.BoolP("enable-early-microcode", "E", true, "Enable installing early microcode firmware")
	hostOnly := flags.BoolP("host-specific", "H", false, "Build a host-specific initramfs")
	sHelp := flags.BoolP("help", "h", false, "Show help information")
	sVersion := flags.BoolP("version", "V", false, "Show version information")
	flags.VarP(compressor, "commpression", "c", "Use a requested type of compression. [allowed: "+strings.Join(compressor.Allowed[:], ", ")+"]")

	// usage flag
	flags.Usage = func() {
		fmt.Fprintln(os.Stderr, VERSION)
		fmt.Fprintln(os.Stderr, "Usage: mkinitramfs [OPTIONS] --file INITRAMFS_FILE -k KERNEL_VERSION")
		fmt.Fprintln(os.Stderr, "\nOptions:")
		flags.PrintDefaults()
	}
	flags.Parse()

	// is help requested?
	if *sHelp {
		flags.Usage()
		os.Exit(0)
	}
	// is version to be shown?
	if *sVersion {
		fmt.Println(VERSION)
		os.Exit(0)
	}

	// assign stuff into the struct
	if &tmpDir != nil {
		config.BuildDirectory = *tmpDir
	} else {
		config.BuildDirectory = ""
	}
	config.CompressionType = compressor.Value
	config.ConfigurationFile = *configFile
	config.KernelModuleDir = *kmodDir
	config.KernelVersion = *kver
	config.Modules = *plugins
	config.UseForce = *useForce
	config.StripBinaries = *stripBinaries
	config.InitramfsFile = *file
	config.HostSpecific = *hostOnly
	if &earlyFirmwareTmpDir != nil {
		config.EarlyFirmwareBuildDir = *earlyFirmwareTmpDir
	} else {
		config.EarlyFirmwareBuildDir = ""
	}
	config.EnableEarlyMicrocode = *enableEarlyMicrocode

	return config
}

func setDefaultModules(config *config.Config) {
	config.Modules = []string{
		"earlyfw",
		"basedirs",
		"busybox",
		"busybox-init",
		"firmware",
		"fstools",
		"kernel-modules",
		"mdev",
		"mdev-rules",
		"rootfs",
		"pivot",
		"compression",
	}
}

func getRunningKernel() string {
	// get the OS' currently running kernel version
	var utsname syscall.Utsname
	if err := syscall.Uname(&utsname); err != nil {
		panic(err)
	}
	kRelease := charsToString(utsname.Release[:])

	return kRelease
}

func displayOptions(config config.Config) {
	fmt.Println("Command options enabled:")
	fmt.Println("Kernel Version:                      " + config.KernelVersion)
	fmt.Println("Using force:                         " + strconv.FormatBool(config.UseForce))
	fmt.Println("Strip installed binaries:            " + strconv.FormatBool(config.StripBinaries))
	fmt.Println("File to write:                       " + config.InitramfsFile)
	fmt.Println("Kernel modules directory:            " + config.KernelModuleDir)
	fmt.Println("Temporary directory:                 " + config.BuildDirectory)
	fmt.Println("Enable early microcode loading:      " + strconv.FormatBool(config.EnableEarlyMicrocode))
	fmt.Println("Early Microcode temporary directory: " + config.EarlyFirmwareBuildDir)
	fmt.Println("Image compression type:              " + config.CompressionType)
	fmt.Println("Configuration JSON:                  " + config.ConfigurationFile)
	fmt.Println("Enabled plugins:                     " + strings.Join(config.Modules, ", "))
	fmt.Println("Build host-specific initramfs:       " + strconv.FormatBool(config.HostSpecific))
}

func main() {
	// set up default configuration
	config := config.Config{}
	// default modules
	setDefaultModules(&config)

	kRelease := getRunningKernel()
	defKModDir := "/lib/modules/" + kRelease

	config = processFlags(kRelease, defKModDir, config)
	displayOptions(config)

	// read configuration
	if _, err := os.Stat(config.ConfigurationFile); errors.Is(err, os.ErrNotExist) {
		// the config doesn't exist, so use sane defaults
		config.SetDefaultConfig(&config)
	} else {
		// file exists, set any base configurations from it
		config.ReadAndApplyConfigFile(&config)
	}

	// create temp directory for the early firmware image
	if config.EnableEarlyMicrocode {
		// do the same for the early microcode archive temp dir
		if *&config.EarlyFirmwareBuildDir == "" {
			earlyFirmwareTmpDirStr, err := os.MkdirTemp(os.TempDir(), "tmp.")
			if err != nil {
				panic(err)
			}

			config.EarlyFirmwareBuildDir = earlyFirmwareTmpDirStr
		}
	} else {
		config.EarlyFirmwareBuildDir = ""
	}

	// create early firmware cpio archive for CPU microcode
	earlyFwArchive, err := earlyfirmware.CreateEarlyFirmwareArchive(config.EarlyFirmwareBuildDir)
	if err != nil {
		panic(err)
	}

	// create temp directory for the main initramfs image
	if config.BuildDirectory == "" {
		// set our temp dir to a real temp dir
		tmpDirStr, err := os.MkdirTemp(os.TempDir(), "tmp.")
		if err != nil {
			panic(err)
		}

		config.BuildDirectory = tmpDirStr
	}

	// loop through plugins

	// create cpio archive for primary initramfs image
	mainArchivePath, err := initramfs.MkMainArchive(config.BuildDirectory)

	// join both the early firmware cpio archive to the main initramfs archive
	cpioFilePath, err := initramfs.MkArchive(earlyFwArchive, mainArchivePath)

	// compress with requested compressor
	compressedInitramfsPath, err := initramfs.CompressInitramFs(cpioFilePath, config.CompressionType)
	if err != nil {
		panic(err)
	}

	// determine permanent file name

	// move into permanent location
	err = os.Rename(compressedInitramfsPath, config.InitramfsFile)

	// clean up
	os.RemoveAll(config.BuildDirectory)
	os.RemoveAll(config.EarlyFirmwareBuildDir)
}
