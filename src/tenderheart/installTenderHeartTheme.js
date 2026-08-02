const TENDERHEART_SCROLLBAR_STYLE_ID = "tenderheart-scrollbar-theme";

const TENDERHEART_SCROLLBAR_CSS = `
/* Chrome / Edge / Brave / Safari */

*::-webkit-scrollbar {
    width: 10px;
    height: 10px;
}

*::-webkit-scrollbar-track {
    background: var(--scrollbar-track, #12151d);
}

*::-webkit-scrollbar-thumb {
    background: var(--scrollbar-thumb, #3c4658);
    border-radius: 999px;
    border: 2px solid var(--scrollbar-track, #12151d);
}

*::-webkit-scrollbar-thumb:hover {
    background: var(--scrollbar-thumb-hover, #556277);
}

*::-webkit-scrollbar-corner {
    background: var(--scrollbar-track, #12151d);
}

/* Firefox */

* {
    scrollbar-width: thin;
    scrollbar-color:
        var(--scrollbar-thumb, #3c4658)
        var(--scrollbar-track, #12151d);
}
`;

export function installTenderHeartTheme() {
    if (typeof document === "undefined") {
        return;
    }

    const existingStyle = document.getElementById(
        TENDERHEART_SCROLLBAR_STYLE_ID
    );

    if (existingStyle) {
        return;
    }

    const style = document.createElement("style");
    style.id = TENDERHEART_SCROLLBAR_STYLE_ID;
    style.dataset.tenderheartTheme = "scrollbars";
    style.textContent = TENDERHEART_SCROLLBAR_CSS;

    document.head.appendChild(style);
}
