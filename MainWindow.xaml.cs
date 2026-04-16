using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using acorn.Pages;

namespace acorn
{
    public sealed partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
            AppWindow.Resize(new Windows.Graphics.SizeInt32(1000, 680));
        }

        private void NavView_Loaded(object sender, RoutedEventArgs e)
        {
            NavView.SelectedItem = NavView.MenuItems[0];
        }

        private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
        {
            if (args.SelectedItem is NavigationViewItem item)
            {
                NavigateTo(item.Tag as string);
            }
        }

        private void NavigateTo(string? tag)
        {
            var pageType = tag switch
            {
                "Backups" => typeof(BackupsPage),
                "Status"  => typeof(StatusPage),
                "Restore" => typeof(RestorePage),
                _         => typeof(BackupsPage)
            };

            if (ContentFrame.CurrentSourcePageType != pageType)
                ContentFrame.Navigate(pageType);
        }
    }
}
