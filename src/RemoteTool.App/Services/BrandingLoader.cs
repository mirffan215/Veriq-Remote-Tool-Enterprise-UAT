using System.Windows.Media.Imaging;
using RemoteTool.Core.Config;

namespace RemoteTool.App.Services;

/// <summary>Reads the branding embedded at build time (RemoteTool.branding.json, RemoteTool.logo.png). Everything is optional.</summary>
public static class BrandingLoader
{
    public static Branding Branding { get; private set; } = Branding.Default;
    public static BitmapImage? Logo { get; private set; }

    public static void Load()
    {
        var asm = typeof(BrandingLoader).Assembly;
        try
        {
            using var s = asm.GetManifestResourceStream("RemoteTool.branding.json");
            if (s is not null) { using var r = new StreamReader(s); Branding = Branding.Parse(r.ReadToEnd()); }
        }
        catch (Exception e) when (e is IOException or InvalidOperationException) { }
        try
        {
            using var s = asm.GetManifestResourceStream("RemoteTool.logo.png");
            if (s is null) return;
            var ms = new MemoryStream();
            s.CopyTo(ms);
            ms.Position = 0;
            var img = new BitmapImage();
            img.BeginInit();
            img.CacheOption = BitmapCacheOption.OnLoad;
            img.StreamSource = ms;
            img.EndInit();
            img.Freeze();
            Logo = img;
        }
        catch (Exception) { Logo = null; }   // a bad logo falls back to no logo
    }
}
