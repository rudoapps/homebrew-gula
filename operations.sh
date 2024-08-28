#!/bin/bash

check_type_of_project() {
	if [ -d "$ANDROID_PROJECT_SRC" ]; then
      return 0
    elif find . -maxdepth 1 -name "*.xcodeproj" | grep -q .; then
      return 1	
    else
      return -1
    fi
}