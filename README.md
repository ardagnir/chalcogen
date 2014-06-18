Chalcogen
===========

Full Vim integration in Atom. Unlike vim-mode, Chalocgen embeds an actual Vim process using [vimbed](https://github.com/ardagnir/vimbed) to give you all of Vim's functionality.

*(Currently in proof-of-concept stage)*

##Requirements
- Chalcogen requires Atom and Vim(your version needs to have +clientserver).
- Chalcogen works best in GNU/Linux.
- Chalcogen also works in OSX, but doing so requires XQuartz. *(This is a requirement of vim's +clientserver functionality.)*

##Setup
**Step 1:** If you don't have the vimbed plugin, install it first using your plugin-manager. If you use pathogen:

    cd ~/.vim/bundle
    git clone http://github.com/ardagnir/vimbed

**Step 2:** Clone chalcogen to your Atom plugin directory

    mkdir ~/.atom/packages
    cd ~/.atom/packages
    git clone http://github.com/ardagnir/chalcogen

**Step 3:** Chalcogen is deactivated by default. Use Chalcogen:toggle or press Control-Alt-v to turn it on.

##What works
- All the main vim modes should work, including ex commands.
- Mouse support works.
- Tabs are mostly working, and you should be able to add/remove tabs using vim commands or the atom-gui, but it's not perfect.

##What doesn't
- There's a lot of bugs. Chalcogen is unfinished and so is Atom.
- Splits aren't supported yet. Atom and Vim handle splits differently and it's going to take some work to implement vim-style splits in Atom.

##License
AGPL v3
