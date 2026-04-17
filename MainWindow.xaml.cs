using acorn.Pages;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace acorn
{
    public sealed partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
            AppWindow.Resize(new Windows.Graphics.SizeInt32(1180, 820));
        }

        private void AppNav_Loaded(object sender, RoutedEventArgs e)
        {
            AppNav.SelectedItem = StatusNavItem;
            NavigateTo("Status");
        }

        private void AppNav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
        {
            if (args.SelectedItem is NavigationViewItem item && item.Tag is string tag)
                NavigateTo(tag);
        }

        private void NavigateTo(string tag)
        {
            var pageType = tag switch
            {
                "Status" => typeof(StatusPage),
                "Settings" => typeof(SettingsPage),
                _ => typeof(BackupSettingsPage)
            };

            if (ContentFrame.CurrentSourcePageType != pageType)
                ContentFrame.Navigate(pageType);
        }
    }
}
