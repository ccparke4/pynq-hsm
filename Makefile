# simple make

.PHONY: all clean help

help:
	@echo "Available commands:"
	@echo "  make clean    - Remove generic temporary files"
	@echo "  make hw       - (Placeholder) Launch Vivado build"
	@echo "  make sw       - (Placeholder) Compile C/C++ app"

clean:
	find . -name "*.log" -delete
	find . -name "*.jou" -delete
	rm -rf .Xil
