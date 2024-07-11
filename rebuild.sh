set -e
pushd ~/Documents/repos/nix
vim configuration.nix
git diff -U0 *.nix
echo "NixOS Rebuilding..."
sudo nixos-rebuild switch &>nixos-switch.log || (
 cat nixos-switch.log | grep --color error && false)
gen=$(nixos-rebuild list-generations | grep current)
git add configuration.nix
git commit -am "$gen"
git push
popd