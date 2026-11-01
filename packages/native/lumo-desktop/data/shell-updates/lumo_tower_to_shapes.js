desktops().forEach(function (desktop) {
    if (desktop.wallpaperPlugin === "org.lumo.tower") {
        desktop.wallpaperPlugin = "org.lumo.shapes";
    }
});
