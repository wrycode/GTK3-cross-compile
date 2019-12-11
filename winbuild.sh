#!/bin/bash
setup () {
    # Create a fedora container
    container=$(buildah from fedora)

    # Install dependencies 
    buildah run $container dnf -y install mingw64-gtk3 mingw32-binutils mingw32-nsiswrapper 

     # Fix typo in mingw library
    buildah run $container bash -c "sed -i -e 's/-Wl,-luuid/-luuid/g' /usr/x86_64-w64-mingw32/sys-root/mingw/lib/pkgconfig/gdk-3.0.pc"

    # Cache image to avoid re-downloading dependencies every time
    buildah commit $container my-tutorial-app

    # Clean up
    buildah rm $container
}

build () {
    # Create a new container from the base one we created
    container=$(buildah from localhost/my-tutorial-app)

    # Folder to hold everything needed for the windows installer:
    output_folder=windows
    yes | rm -r $output_folder
    mkdir $output_folder

    # Directory of your package in the container
    folder=/root/app

    # Copy program into container
    buildah copy $container . $folder

    # Name for the executable file on Windows
    executable_name="Demo.exe"

    # make some folders we'll need
    buildah run $container bash -c "cd $folder && mkdir -p $output_folder/share/themes $output_folder/etc/gtk-3.0"

    # generate a RC file with the windres utility to embed an icon into the .exe later on
    buildah run $container bash -c "cd $folder && x86_64-w64-mingw32-windres icon.rc -O coff -o icon.res"

    # copy some project resources
    buildah run $container bash -c "cd $folder && cp -r Windows10 $output_folder/share/themes && \
    cp settings.ini $output_folder/etc/gtk-3.0/ &&\
    cp icon.ico $output_folder"

    # Compile program
    buildah run $container bash -c "cd $folder && x86_64-w64-mingw32-gcc -mwindows -o $executable_name main.c icon.res \`mingw64-pkg-config --cflags gtk+-3.0 --libs gtk+-3.0\`"

    # Copy executable into installation folder
    buildah run $container bash -c "cd $folder && cp $executable_name $output_folder"

    # Copy mingw dlls into installation folder
    # This part may need to be personalized
    buildah run $container bash -c "yes | cp -r /usr/x86_64-w64-mingw32/sys-root/mingw/{bin/*.dll,share} $folder/$output_folder/"

    # Generate an installer
    buildah run $container bash -ic "cd $folder/$output_folder && nsiswrapper --run $executable_name ./*"

    # Copy the output from the container
    cp -ru $(buildah unshare buildah mount $container)$folder/$output_folder .

    # Clean up
    buildah rm $container
}

# This just checks whether the container already exists on your drive
buildah inspect localhost/my-tutorial-app &>/dev/null
return_value=$?

if [ $return_value -eq 1 ]
then
    echo "Initial container setup"
    setup
fi

# Build project
build
