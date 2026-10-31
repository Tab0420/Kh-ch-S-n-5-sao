using System.Web;
using System.Web.Mvc;

namespace Khách_Sạn_5_sao
{
    public class FilterConfig
    {
        public static void RegisterGlobalFilters(GlobalFilterCollection filters)
        {
            filters.Add(new HandleErrorAttribute());
        }
    }
}
