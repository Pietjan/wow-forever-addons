# The repo that copies addons into the game (mine is not public; see README).
MANAGER ?= ../wow-addons

.DEFAULT_GOAL := help
.PHONY: help check guides install

help:
	@echo "make check     compile every addon and look for locals used before definition"
	@echo "make guides    fetch the RestedXP and WoW-Pro guide files that ForeverGuide reads"
	@echo "make install   check, then let $(MANAGER) copy the addons into the game"

check:
	@python3 -I scripts/check-lua.py

# ForeverGuide loads the guide files of RestedXP Guides and WoW-Pro as they
# are published; this takes fresh copies (see scripts/guides.py).
guides:
	@python3 -I scripts/guides.py

install:
	@test -f "$(MANAGER)/Makefile" || { echo "No $(MANAGER): copy the folders under addons/ into the game's Interface/AddOns by hand."; exit 1; }
	@$(MAKE) --no-print-directory -C "$(MANAGER)" install
