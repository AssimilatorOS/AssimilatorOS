package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"

	flags "github.com/spf13/pflag"

	"github.com/greeneg/AssimilatorOS/src/mkinitramfs/config"
)

const defaultPlugins = "busybox, busybox-init, kernel-modules, mdev, mdev-rules, fs, compression"
const VERSION = "mkinitramfs 0.0.1"

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

func processFlags(kRelease string, defKModDir string, config config.Config ) (config.Config) {
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
	sHelp := flags.BoolP("help", "h", false, "Show help information")
	sVersion := flags.BoolP("version", "V", false, "Show version information")
	flags.VarP(compressor, "commpression", "c", "Use a requested type of compression. [allowed: " + strings.Join(compressor.Allowed[:], ", ") + "]")

	// usage flag
	flags.Usage = func() {
		fmt.Fprintln(os.Stderr, VERSION)
		fmt.Fprintln(os.Stderr, "Usage: mkinitramfs [OPTIONS] --file INITRAMFS_FILE -k KERNEL_VERSION")
		fmt.Fprintln(os.Stderr, "\nOptions:")
		flags.PrintDefaults()
	}
	flags.Parse()

	if *tmpDir == "" {
		// set our temp dir to a real temp dir
		tmpDirStr, err := os.MkdirTemp(os.TempDir(), "tmp.")
		if err != nil {
			panic(err)
		}

		tmpDir = &tmpDirStr
	}

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
	config.BuildDirectory = *tmpDir
	config.CompressionType = compressor.Value
	config.ConfigurationFile = *configFile
	config.KernelModuleDir = *kmodDir
	config.KernelVersion = *kver
	config.Modules = *plugins
	config.UseForce = *useForce
	config.StripBinaries = *stripBinaries
	config.InitramfsFile = *file

	return config
}

func setDefaultModules(config *config.Config) {
	config.Modules = []string{
		"00earlyfw",
		"01base",
		"02busybox",
		"03busybox-init",
		"04firmware",
		"05fs",
		"06kernel-modules",
		"07mdev",
		"08mdev-rules",
		"09rootfs",
		"10pivot",
		"11compression",
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
	fmt.Println("Kernel Version:           " + config.KernelVersion)
	fmt.Println("Using force:              " + strconv.FormatBool(config.UseForce))
	fmt.Println("Strip installed binaries: " + strconv.FormatBool(config.StripBinaries))
	fmt.Println("File to write:            " + config.InitramfsFile)
	fmt.Println("Kernel modules directory: " + config.KernelModuleDir)
	fmt.Println("Temporary directory:      " + config.BuildDirectory)
	fmt.Println("Image compression type:   " + config.CompressionType)
	fmt.Println("Configuration JSON:       " + config.ConfigurationFile)
	fmt.Println("Enabled plugins:          " + strings.Join(config.Modules, ", "))
}

func main () {
	// set up default configuration
	config := config.Config{}
	// default modules
	setDefaultModules(&config)

	kRelease := getRunningKernel()
	defKModDir := "/lib/modules/" + kRelease

	config = processFlags(kRelease, defKModDir, config)
	displayOptions(config)

	// read configuration

	// create temp directory

	// build initrd directory tree and symlinks

	// loop through plugins

	// create cpio archive

	// compress with requested compressor

	// clean up
	os.RemoveAll(config.BuildDirectory)
}
