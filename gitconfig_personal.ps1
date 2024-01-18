param(
	[switch]$local
)

if ($local) {
	git config  user.name "mudssky"
	git config  user.email "mudssky@gmail.com"
	exit
}
git config --global user.name "mudssky"
git config --global user.email "mudssky@gmail.com"