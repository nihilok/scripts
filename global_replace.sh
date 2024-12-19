#!/bin/bash

# Check for the correct number of arguments
if [ $# -ne 3 ]; then
    echo "Usage: $0 <directory> <old-text> <new-text>"
    exit 1
fi

echo "Replacing $2 with $3 for files in ${1}; This may take a while depending on the number of files in the directory."
find $1 -type f -print0 | xargs -0 sed -i "s/$2/$3/g"
echo "Done."

