# Instalation instruction
- From [origin of this plugin](https://github.com/jereyes4/xournalpp-bookmarks)
- Thanks for the wonderful plugin jereyes4!

# Changes (commit [89303](https://github.com/TamadoIchikai/xournalpp-bookmarks/commit/8930387bbbfd29fb1352b69ec6c8f2aac099a09e))
- Tested on [1.3.4](https://github.com/xournalpp/xournalpp/releases/tag/v1.3.4)
- Shortcuts `ctrl+b` and `ctrl+shift+b` to create bookmark and open bookmarks manager.
- Bookmark layer now alway sorted bellow the drawing layer (note that the drawing layer should be named "Layer 1",..., "Layer n", which mean im never rename a layer).
- Double click to Jump to bookmarks and Double click on the bookmark name to edit (note that because of GTK limitation, double click to edit the bookmark is based on the longest bookmark name in the "Name" column, not the actual individual bookmark).
- Bookmarks in the same page will be sorted alphabetically.

# New Changes 
- Tested on [1.3.4 nightly](https://github.com/xournalpp/xournalpp/releases/tag/nightly)
- Changed shortcuts `b` and `shift+b`
- Now bookmarks don't rely on layer anymore but rely on text element.
- I use symbol to quickly identify level where "`*`" symbol is highest level symbol and "->", "-->","--->",... will be second, third,... level symbol.
- When create new bookmark via new bookmark shortcut or on toolbar, it will create a text at top left of current page and only create if symbol "`*`", "-", ">" exist before the text. Newly created text element will be based on current font where "`*`" will be bold and font size 25, "->" will be italic and font size 20, "-->" "--->" will be regular and font size decrease by 5 each level (minimum 15). Notice that you can also use add text function of native xournalpp on toolbar, just remember to type `*` or "->", "-->" before the text content
- Change view bookmark window accordingly.
