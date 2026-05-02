.PHONY: link unlink

PLUGIN_DIR := $(HOME)/.claude/plugins/image

link:
	mkdir -p $(HOME)/.claude/plugins
	rm -rf $(PLUGIN_DIR)
	ln -s $(CURDIR) $(PLUGIN_DIR)
	@echo "linked: $(PLUGIN_DIR) -> $(CURDIR)"

unlink:
	rm -f $(PLUGIN_DIR)
	@echo "unlinked: $(PLUGIN_DIR)"
