### Setup Caddie on arm64 (macOS M1):
1. Download repository from: https://github.com/diku-dk/caddie
2. Install MLton using Homebrew (arm64): ```brew install mlton```
3. Install MLKIT using Homebrew with Rosetta2:
   1. type ```arch -x86_64 zsh``` in the command line to switch to rosetta terminal
   2. Make sure Homebrew is installed for Rosetta. To install use command ``` arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"```
   3. Set ```HOMEBREW_PREFIX``` to ```usr/local``` by adding ```export PATH="/usr/local/bin:$PATH"``` to ```~/.zshrc``` file.  
   This is done by typing: ```nano ~/.zshrc```, copy-paste  ```export PATH="/usr/local/bin:$PATH"``` into the file, type ```^x```, ```y```, and ```enter```, for saving and exit nano.  
   In the terminal update hombrew by typing ```source ~/.zshrc```.  
   Type ```brew config``` and check that ```HOMEPREW_PREFIX``` path is set to ```HOMEBREW_PREFIX: /usr/local```.
   4. Install ```brew install mlkit```
   5. Install ```brew install smlpkg```
   6. (use ```brew list``` to make sure ```gmp mlkit smlpkg``` are installed)
   7. Set ```HOMEBREW_PREFIX``` back to arm64 default by adding ```export PATH="/opt/homebrew/bin:$PATH"``` to ```~/.zshrc``` (replacing the ```/usr/local/``` path). See above.

### To switch between Rosetta and ARM in the terminal use:  
Rosetta2 (Intel): ```arch -x86_64 zsh```  
ARM: ```arch -arm64 zsh```

### Run Caddie in the terminal
1. To compile the program, type ```make all```. 
   1. to run the program type ```./src/cad```
   2. use ```./src/cad --help``` for instructions
2. To run tests, type command ```make test``` in the caddie folder

### 