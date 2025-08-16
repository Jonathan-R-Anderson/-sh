DC ?= ldc2
SRC := $(wildcard src/*.d)
TARGET := lfe-sh

.RECIPEPREFIX := >

$(TARGET): $(SRC)
>$(DC) $(SRC) -L-lreadline -of=$(TARGET)

.PHONY: clean
clean:
>rm -f $(TARGET)

