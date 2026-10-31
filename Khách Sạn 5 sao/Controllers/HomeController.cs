using Khách_Sạn_5_sao.Models;
using System;
using System.Collections.Generic;
using System.Data.Entity;
using System.Linq;
using System.Web;
using System.Web.Mvc;

namespace Khách_Sạn_5_sao.Controllers
{
    public class HomeController : Controller
    {
        booking_dbEntities database = new booking_dbEntities();
        public ActionResult TrangChu()
        {
            return View();
        }

        public ActionResult About()
        {
            ViewBag.Message = "Your application description page.";

            return View();
        }

        public ActionResult Contact()
        {
            return View();
        }

        public ActionResult PhongNghi()
        {
            return View();
        }

        public ActionResult AmThuc()
        {
            return View();
        }
        public ActionResult UuDai()
        {
            return View();
        }
        public ActionResult DichVu()
        {
            return View();
        }
        public ActionResult TienIch()
        {
            return View();
        }
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Contact(string name, string email, string phone, string subject, string message)
        {
            if (string.IsNullOrWhiteSpace(name) ||
                string.IsNullOrWhiteSpace(email) ||
                string.IsNullOrWhiteSpace(subject) ||
                string.IsNullOrWhiteSpace(message))
            {
                ModelState.AddModelError(
                    "",
                    "Vui lòng nhập đầy đủ các thông tin bắt buộc.");

                return View();
            }

            // Hiện tại chỉ tiếp nhận và kiểm tra dữ liệu.
            // Chưa lưu cơ sở dữ liệu hoặc gửi email.

            ViewBag.SuccessMessage =
                "Thông tin đã được tiếp nhận trong phiên xử lý này.";

            return View();
        }
        public ActionResult DanhSachPhong(string loaiPhong)
        {
            ViewBag.LoaiPhong = loaiPhong;
            return View();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                database.Dispose();
            }
            base.Dispose(disposing);
        }
        // GET: Home/DanhSachPhong?loaiPhong=Superior

    }
}
