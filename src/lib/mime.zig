const std = @import("std");
const mem = std.mem;

pub const Mime = enum {
    // Text types
    text_plain,
    text_html,
    text_css,
    text_javascript,
    text_csv,
    text_xml,

    // Application types
    application_json,
    application_xml,
    application_octet_stream,
    application_pdf,
    application_zip,
    application_x_www_form_urlencoded,
    application_javascript,

    // Image types
    image_jpeg,
    image_png,
    image_gif,
    image_svg_xml,
    image_webp,
    image_avif,

    // Audio types
    audio_mpeg,
    audio_ogg,
    audio_wav,

    // Video types
    video_mp4,
    video_webm,
    video_ogg,

    // Font types
    font_woff,
    font_woff2,
    font_ttf,
    font_otf,

    /// Get MIME type from file extension (e.g. "html" -> text_html)
    pub fn fromExtension(ext: []const u8) ?Mime {
        // Handle empty input
        if (ext.len == 0) return null;

        // Make a lowercase copy we can work with
        var lowercase_buf: [16]u8 = undefined;
        const len = @min(ext.len, lowercase_buf.len);
        var lowercase_ext = lowercase_buf[0..len];

        for (ext[0..len], 0..) |c, i| {
            lowercase_ext[i] = std.ascii.toLower(c);
        }

        // Compare with known extensions
        if (mem.eql(u8, lowercase_ext, "txt")) return .text_plain;
        if (mem.eql(u8, lowercase_ext, "html") or mem.eql(u8, lowercase_ext, "htm")) return .text_html;
        if (mem.eql(u8, lowercase_ext, "css")) return .text_css;
        if (mem.eql(u8, lowercase_ext, "js")) return .application_javascript;
        if (mem.eql(u8, lowercase_ext, "csv")) return .text_csv;
        if (mem.eql(u8, lowercase_ext, "xml")) return .text_xml;
        if (mem.eql(u8, lowercase_ext, "json")) return .application_json;
        if (mem.eql(u8, lowercase_ext, "pdf")) return .application_pdf;
        if (mem.eql(u8, lowercase_ext, "zip")) return .application_zip;
        if (mem.eql(u8, lowercase_ext, "bin") or
            mem.eql(u8, lowercase_ext, "exe") or
            mem.eql(u8, lowercase_ext, "dll")) return .application_octet_stream;
        if (mem.eql(u8, lowercase_ext, "jpg") or mem.eql(u8, lowercase_ext, "jpeg")) return .image_jpeg;
        if (mem.eql(u8, lowercase_ext, "png")) return .image_png;
        if (mem.eql(u8, lowercase_ext, "gif")) return .image_gif;
        if (mem.eql(u8, lowercase_ext, "svg")) return .image_svg_xml;
        if (mem.eql(u8, lowercase_ext, "webp")) return .image_webp;
        if (mem.eql(u8, lowercase_ext, "avif")) return .image_avif;
        if (mem.eql(u8, lowercase_ext, "mp3")) return .audio_mpeg;
        if (mem.eql(u8, lowercase_ext, "ogg") or mem.eql(u8, lowercase_ext, "oga")) return .audio_ogg;
        if (mem.eql(u8, lowercase_ext, "wav")) return .audio_wav;
        if (mem.eql(u8, lowercase_ext, "mp4")) return .video_mp4;
        if (mem.eql(u8, lowercase_ext, "webm")) return .video_webm;
        if (mem.eql(u8, lowercase_ext, "ogv")) return .video_ogg;
        if (mem.eql(u8, lowercase_ext, "woff")) return .font_woff;
        if (mem.eql(u8, lowercase_ext, "woff2")) return .font_woff2;
        if (mem.eql(u8, lowercase_ext, "ttf")) return .font_ttf;
        if (mem.eql(u8, lowercase_ext, "otf")) return .font_otf;

        return null;
    }

    /// Convert to proper HTTP MIME type string
    pub fn toHttpString(self: Mime) []const u8 {
        return switch (self) {
            .text_plain => "text/plain",
            .text_html => "text/html",
            .text_css => "text/css",
            .text_javascript => "text/javascript",
            .text_csv => "text/csv",
            .text_xml => "text/xml",
            .application_json => "application/json",
            .application_xml => "application/xml",
            .application_octet_stream => "application/octet-stream",
            .application_pdf => "application/pdf",
            .application_zip => "application/zip",
            .application_x_www_form_urlencoded => "application/x-www-form-urlencoded",
            .application_javascript => "application/javascript",
            .image_jpeg => "image/jpeg",
            .image_png => "image/png",
            .image_gif => "image/gif",
            .image_svg_xml => "image/svg+xml",
            .image_webp => "image/webp",
            .image_avif => "image/avif",
            .audio_mpeg => "audio/mpeg",
            .audio_ogg => "audio/ogg",
            .audio_wav => "audio/wav",
            .video_mp4 => "video/mp4",
            .video_webm => "video/webm",
            .video_ogg => "video/ogg",
            .font_woff => "font/woff",
            .font_woff2 => "font/woff2",
            .font_ttf => "font/ttf",
            .font_otf => "font/otf",
        };
    }
};

test "mime" {
    const mime = Mime.fromExtension("js");

    std.debug.print("\n{?}\n", .{mime.?});
    std.debug.print("{s}\n", .{mime.?.toHttpString()});
}
