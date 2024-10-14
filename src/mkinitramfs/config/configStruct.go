package config

type Config struct {
	BuildDirectory string
	CompressionType string
	ConfigurationFile string
	InitramfsFile string
	KernelModuleDir string
	KernelVersion string
	Modules []string
	StripBinaries bool
	UseForce bool
}
