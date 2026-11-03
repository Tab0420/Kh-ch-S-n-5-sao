using Khách_Sạn_5_sao.Models;
using System;
using System.Collections.Generic;
using System.Data.Entity;
using System.Linq;
using System.Web;
using System.Web.Mvc;

namespace Khách_Sạn_5_sao.Controllers
{
    public class BookingsController : Controller
    {
        booking_dbEntities database = new booking_dbEntities();

        public class RoomNameRow
        {
            public string RoomId { get; set; }
            public string Name { get; set; }
        }

        private Dictionary<string, string> RoomNames()
        {
            return database.Database.SqlQuery<RoomNameRow>(
                "SELECT room_id AS RoomId, ten_phong AS Name FROM dbo.Rooms")
                .ToList()
                .ToDictionary(
                    r => r.RoomId,
                    r => string.IsNullOrWhiteSpace(r.Name)
                        ? "Phòng nghỉ" : r.Name);
        }

        public class RoomPhotoRow
        {
            public string RoomId { get; set; }
            public string ImageUrl { get; set; }
        }

        private Dictionary<string, string> RoomPhotos()
        {
            return database.Database.SqlQuery<RoomPhotoRow>(
                "SELECT room_id AS RoomId, hinh_anh AS ImageUrl FROM dbo.Rooms")
                .ToList()
                .ToDictionary(r => r.RoomId, r => r.ImageUrl ?? "");
        }

        public class ExtraOption
        {
            public string Id { get; set; }
            public string Name { get; set; }
            public decimal Price { get; set; }
        }

        private List<ExtraOption> ExtraOptions()
        {
            return new List<ExtraOption>
            {
                new ExtraOption
                {
                    Id = "airport",
                    Name = "Đưa đón sân bay 2 chiều",
                    Price = 300000
                },
                new ExtraOption
                {
                    Id = "breakfast",
                    Name = "Buffet sáng đặc biệt",
                    Price = 150000
                },
                new ExtraOption
                {
                    Id = "motorbike",
                    Name = "Thuê xe máy (24h)",
                    Price = 120000
                }
            };
        }

        public class DiscountRow
        {
            public string Code { get; set; }
            public decimal Percent { get; set; }
            public string Kind { get; set; }
        }

        private DiscountRow FindDiscount(
            string code, string phone, DateTime start, DateTime end)
        {
            if (string.IsNullOrWhiteSpace(code) || code.Length > 32)
                return null;

            var discount = database.Database.SqlQuery<DiscountRow>(@"
                SELECT code AS Code,discount_percent AS [Percent],kind AS Kind
                FROM dbo.DiscountCodes
                WHERE code = @p0
                  AND enabled = 1
                  AND (valid_from IS NULL OR valid_from <= @p1)
                  AND (valid_to IS NULL OR valid_to >= @p1)",
                code.Trim().ToUpperInvariant(),
                HotelToday()).FirstOrDefault();

            if (discount == null) return null;

            phone = (phone ?? "").Trim();
            if (phone.StartsWith("+84"))
                phone = "0" + phone.Substring(3);

            var history = database.Bookings.Where(
                b => b.User.so_dien_thoai == phone
                    && (b.trang_thai == null || b.trang_thai != "Đã hủy"));

            if (discount.Kind == "NEW" && history.Any())
                return null;

            DateTime now = DateTime.UtcNow.AddHours(7);
            DateTime cutoff = now.AddYears(-1);

            if (discount.Kind == "VIP"
                && history.Count(
                    b => b.ngay_dat >= cutoff && b.ngay_dat <= now) < 12)
                return null;

            if (discount.Kind == "HOLIDAY"
                && database.Database.SqlQuery<int>(@"
                    SELECT COUNT(*) FROM dbo.HolidayDates
                    WHERE holiday_date >= @p0 AND holiday_date < @p1",
                    start, end).Single() == 0)
                return null;

            return discount;
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public JsonResult CheckDiscount(
            string coupon_code,
            string so_dien_thoai,
            DateTime? ngay_checkin,
            DateTime? ngay_checkout)
        {
            if (!System.Text.RegularExpressions.Regex.IsMatch(
                so_dien_thoai ?? "", @"^(0|\+84)[35789][0-9]{8}$"))
            {
                return Json(new
                {
                    success = false,
                    discountPercent = 0,
                    message = "Vui lòng nhập số điện thoại hợp lệ trước."
                });
            }

            if (!ngay_checkin.HasValue || !ngay_checkout.HasValue
                || !ValidStay(
                    ngay_checkin.Value.Date, ngay_checkout.Value.Date))
            {
                return Json(new
                {
                    success = false,
                    discountPercent = 0,
                    message = "Vui lòng chọn ngày lưu trú hợp lệ."
                });
            }

            var discount = FindDiscount(
                coupon_code, so_dien_thoai,
                ngay_checkin.Value.Date, ngay_checkout.Value.Date);

            if (discount == null)
            {
                return Json(new
                {
                    success = false,
                    discountPercent = 0,
                    message = "Mã không hợp lệ, hết hạn hoặc bạn chưa đủ điều kiện áp dụng."
                });
            }

            return Json(new
            {
                success = true,
                discountPercent = discount.Percent,
                message = "Áp dụng mã giảm "
                    + discount.Percent.ToString("0.##") + "%."
            });
        }

        [HttpGet]
        public JsonResult Availability(
            int type_id,
            DateTime? ngay_checkin,
            DateTime? ngay_checkout)
        {
            if (!ngay_checkin.HasValue || !ngay_checkout.HasValue
                || !ValidStay(
                    ngay_checkin.Value.Date, ngay_checkout.Value.Date))
            {
                return Json(new
                {
                    success = false,
                    message = "Vui lòng chọn khoảng ngày hợp lệ."
                }, JsonRequestBehavior.AllowGet);
            }

            var type = database.Room_Types.Find(type_id);

            if (type == null || !type.gia_tien.HasValue)
            {
                return Json(new
                {
                    success = false,
                    message = "Loại phòng không hợp lệ."
                }, JsonRequestBehavior.AllowGet);
            }

            var names = RoomNames();
            var photos = RoomPhotos();

            var rooms = AvailableRooms(
                ngay_checkin.Value.Date, ngay_checkout.Value.Date)
                .Where(r => r.type_id == type_id)
                .OrderBy(r => r.room_id)
                .ToList()
                .Select(r => new
                {
                    id = r.room_id,
                    name = names[r.room_id],
                    image = photos[r.room_id]
                }).ToList();

            return Json(new
            {
                success = true,
                rooms = rooms,
                rate = type.gia_tien.Value,
                capacity = type.suc_chua ?? 2
            }, JsonRequestBehavior.AllowGet);
        }

        private void LoadReserveData(Room room, DateTime start, DateTime end)
        {
            ViewBag.CheckIn = start;
            ViewBag.CheckOut = end;
            ViewBag.Today = HotelToday();
            ViewBag.RoomNames = RoomNames();
            ViewBag.RoomPhotos = RoomPhotos();

            var choices = AvailableRooms(start, end)
                .Where(r => r.type_id == room.type_id)
                .OrderBy(r => r.room_id).ToList();

            ViewBag.AvailableCount = choices.Count;
            ViewBag.RoomChoices = choices;
            ViewBag.Services = ExtraOptions();

            ViewBag.ResidentBenefits = database.Database
                .SqlQuery<ResidentServicesController.ServiceRow>(
                    ResidentServicesController.CatalogSql)
                .ToList().Where(x => !x.IsCombo).ToList();
        }

        private DateTime HotelToday()
        {
            return DateTime.UtcNow.AddHours(7).Date;
        }

        private bool ValidStay(DateTime start, DateTime end)
        {
            if (start < HotelToday())
                ModelState.AddModelError(
                    "", "Ngày nhận phòng không được ở quá khứ.");

            if (end <= start)
                ModelState.AddModelError(
                    "", "Ngày trả phòng phải sau ngày nhận phòng.");

            return ModelState.IsValid;
        }

        private IQueryable<Room> AvailableRooms(DateTime start, DateTime end)
        {
            return database.Rooms
                .Include(r => r.Room_Types)
                .Where(r =>
                    r.Room_Types != null
                    && r.Room_Types.gia_tien.HasValue
                    && r.Room_Types.gia_tien.Value >= 0
                    && !r.Booking_Details.Any(d =>
                        d.Booking != null
                        && (d.Booking.trang_thai == null
                            || d.Booking.trang_thai != "Đã hủy")
                        && d.Booking.ngay_checkin < end
                        && d.Booking.ngay_checkout > start));
        }

        [HttpGet]
        public ActionResult Index(
            DateTime? ngay_checkin,
            DateTime? ngay_checkout,
            int? type_id,
            string loaiPhong)
        {
            DateTime start = (ngay_checkin ?? HotelToday()).Date;
            DateTime end = (ngay_checkout ?? start.AddDays(1)).Date;

            var types = database.Room_Types.OrderBy(t => t.type_id).ToList();

            if (!type_id.HasValue && !string.IsNullOrWhiteSpace(loaiPhong))
            {
                var names = new Dictionary<string, string>(
                    StringComparer.OrdinalIgnoreCase)
                {
                    { "Superior", "Superior" },
                    { "Deluxe", "Deluxe" },
                    { "HuongBien", "Hướng Biển" },
                    { "GiaDinh", "Gia Đình" },
                    { "Suite", "Suite" },
                    { "CaoCap", "Cao Cấp" }
                };

                string label;
                if (!names.TryGetValue(loaiPhong, out label))
                    label = loaiPhong;

                var match = types.FirstOrDefault(
                    t => t.ten_loai == label || t.ten_loai == "Phòng " + label);

                if (match == null)
                    ModelState.AddModelError("", "Loại phòng không hợp lệ.");
                else
                    type_id = match.type_id;
            }

            if (type_id.HasValue
                && !types.Any(t => t.type_id == type_id.Value))
                ModelState.AddModelError("", "Loại phòng không hợp lệ.");

            ViewBag.CheckIn = start;
            ViewBag.CheckOut = end;
            ViewBag.Today = HotelToday();
            ViewBag.RoomNames = RoomNames();
            ViewBag.RoomPhotos = RoomPhotos();
            ViewBag.RoomTypes = new SelectList(
                types, "type_id", "ten_loai", type_id);

            if (!ValidStay(start, end))
                return View(new List<Room>());

            var rooms = AvailableRooms(start, end);

            if (type_id.HasValue)
                rooms = rooms.Where(r => r.type_id == type_id.Value);

            return View(
                rooms.OrderBy(r => r.type_id)
                    .ThenBy(r => r.room_id).ToList());
        }

        [HttpGet]
        public ActionResult Reserve(
            string room_id,
            DateTime? ngay_checkin,
            DateTime? ngay_checkout)
        {
            DateTime start = (ngay_checkin ?? HotelToday()).Date;
            DateTime end = (ngay_checkout ?? start.AddDays(1)).Date;

            if (!ValidStay(start, end))
                return new HttpStatusCodeResult(400, "Invalid stay dates");

            var room = AvailableRooms(start, end)
                .FirstOrDefault(r => r.room_id == room_id);

            if (room == null)
            {
                TempData["RoomMessage"] =
                    "Phòng không tồn tại hoặc không còn trống trong khoảng ngày đã chọn.";

                return RedirectToAction("Index", new
                {
                    ngay_checkin = start.ToString("yyyy-MM-dd"),
                    ngay_checkout = end.ToString("yyyy-MM-dd")
                });
            }

            LoadReserveData(room, start, end);
            return View(room);
        }

        [HttpPost, ActionName("Reserve")]
        [ValidateAntiForgeryToken]
        public ActionResult ReserveConfirmed(
            string room_id,
            DateTime? ngay_checkin,
            DateTime? ngay_checkout,
            string ho_ten,
            string so_dien_thoai,
            string email,
            string ghi_chu,
            int so_nguoi_lon = 1,
            int so_tre_em = 0,
            int quantity = 1,
            string[] services = null,
            string coupon_code = null)
        {
            var room = database.Rooms
                .Include(r => r.Room_Types)
                .FirstOrDefault(r => r.room_id == room_id);

            if (room == null || room.Room_Types == null
                || !room.Room_Types.gia_tien.HasValue)
                return HttpNotFound();

            DateTime start = (ngay_checkin ?? HotelToday()).Date;
            DateTime end = (ngay_checkout ?? start.AddDays(1)).Date;

            if (!ngay_checkin.HasValue || !ngay_checkout.HasValue)
                ModelState.AddModelError(
                    "", "Vui lòng chọn đủ ngày nhận và trả phòng.");

            ValidStay(start, end);

            if (quantity < 1 || quantity > 100)
                ModelState.AddModelError("", "Số lượng phòng không hợp lệ.");

            var serviceKeys = (services ?? new string[0]).Distinct().ToList();
            var extras = ExtraOptions()
                .Where(x => serviceKeys.Contains(x.Id)).ToList();

            if (extras.Count != serviceKeys.Count)
                ModelState.AddModelError("", "Dịch vụ đã chọn không hợp lệ.");

            coupon_code = (coupon_code ?? "").Trim().ToUpperInvariant();

            if (coupon_code.Length > 32)
                ModelState.AddModelError(
                    "", "Mã giảm giá tối đa 32 ký tự.");

            ho_ten = (ho_ten ?? "").Trim();
            so_dien_thoai = (so_dien_thoai ?? "").Trim();

            if (so_dien_thoai.StartsWith("+84"))
                so_dien_thoai = "0" + so_dien_thoai.Substring(3);

            email = (email ?? "").Trim();

            if (ho_ten.Length == 0 || ho_ten.Length > 255)
                ModelState.AddModelError(
                    "", "Vui lòng nhập họ tên, tối đa 255 ký tự.");

            if (!System.Text.RegularExpressions.Regex.IsMatch(
                so_dien_thoai, @"^(0|\+84)[35789][0-9]{8}$"))
                ModelState.AddModelError(
                    "", "Số điện thoại Việt Nam không hợp lệ.");

            if (email.Length == 0 || email.Length > 255
                || !new System.ComponentModel.DataAnnotations
                    .EmailAddressAttribute().IsValid(email))
                ModelState.AddModelError(
                    "", "Vui lòng nhập email hợp lệ, tối đa 255 ký tự.");

            if (so_nguoi_lon < 1 || so_tre_em < 0
                || (long)so_nguoi_lon + so_tre_em
                    > (long)(room.Room_Types.suc_chua ?? 2) * quantity)
                ModelState.AddModelError(
                    "", "Số khách vượt sức chứa của phòng hoặc không hợp lệ.");

            if ((ghi_chu ?? "").Length > 500)
                ModelState.AddModelError("", "Ghi chú tối đa 500 ký tự.");

            if (ModelState.IsValid)
            {
                using (var tx = database.Database.BeginTransaction(
                    System.Data.IsolationLevel.Serializable))
                {
                    try
                    {
                        int guestLock = database.Database.SqlQuery<int>(@"
                            DECLARE @result int;
                            EXEC @result = sys.sp_getapplock
                                @Resource = @p0,
                                @LockMode = 'Exclusive',
                                @LockOwner = 'Transaction',
                                @LockTimeout = 10000;
                            SELECT @result;",
                            "booking:phone:" + so_dien_thoai).Single();

                        if (guestLock < 0)
                            throw new System.Data.Entity.Core.EntityException(
                                "Khách đang có yêu cầu đặt phòng khác.");

                        database.Database.SqlQuery<int>(@"
                            SELECT type_id
                            FROM dbo.Room_Types WITH (UPDLOCK,HOLDLOCK)
                            WHERE type_id = @p0",
                            room.type_id.Value).Single();

                        var currentRoom = AvailableRooms(start, end)
                            .AsNoTracking()
                            .FirstOrDefault(r => r.room_id == room_id);

                        if (currentRoom == null)
                            ModelState.AddModelError("",
                                "Phòng vừa được đặt trong khoảng ngày này. Vui lòng chọn phòng hoặc ngày khác.");

                        var available = AvailableRooms(start, end)
                            .AsNoTracking()
                            .Where(r => r.type_id == room.type_id)
                            .OrderBy(r => r.room_id).ToList();

                        if (quantity > available.Count)
                            ModelState.AddModelError("",
                                "Không còn đủ số phòng trong khoảng ngày đã chọn.");

                        if (currentRoom != null
                            && (long)so_nguoi_lon + so_tre_em
                                > (long)(currentRoom.Room_Types.suc_chua ?? 2)
                                    * quantity)
                            ModelState.AddModelError("",
                                "Số khách vượt sức chứa hiện tại của phòng.");

                        var discount = FindDiscount(
                            coupon_code, so_dien_thoai, start, end);

                        if (coupon_code.Length > 0 && discount == null)
                            ModelState.AddModelError("",
                                "Mã giảm giá không hợp lệ, hết hạn hoặc bạn chưa đủ điều kiện.");

                        var user = database.Users.FirstOrDefault(
                            u => u.so_dien_thoai == so_dien_thoai);

                        if (user == null && database.Users.Any(u => u.email == email))
                            ModelState.AddModelError("",
                                "Email đã được sử dụng với số điện thoại khác.");

                        if (ModelState.IsValid)
                        {
                            if (user == null)
                            {
                                user = new User
                                {
                                    ho_ten = ho_ten,
                                    so_dien_thoai = so_dien_thoai,
                                    email = email,
                                    vai_tro = "Khách hàng"
                                };
                                database.Users.Add(user);
                            }

                            decimal rate = currentRoom.Room_Types.gia_tien.Value;
                            decimal serviceTotal = extras.Sum(x => x.Price);
                            decimal subtotal =
                                rate * (end - start).Days * quantity + serviceTotal;

                            decimal percent = discount == null ? 0 : discount.Percent;
                            decimal discountAmount = decimal.Round(
                                subtotal * percent / 100m, 0,
                                MidpointRounding.AwayFromZero);

                            var booking = new Booking
                            {
                                User = user,
                                ngay_checkin = start,
                                ngay_checkout = end,
                                ngay_dat = DateTime.UtcNow.AddHours(7),
                                so_nguoi_lon = so_nguoi_lon,
                                so_tre_em = so_tre_em,
                                tong_tien = subtotal - discountAmount,
                                ghi_chu = ghi_chu,
                                trang_thai = "Chờ thanh toán",
                                phuong_thuc_tt = "Thanh toán tại khách sạn"
                            };

                            database.Bookings.Add(booking);

                            var selectedIds = new List<string> { room_id };
                            selectedIds.AddRange(
                                available.Where(r => r.room_id != room_id)
                                    .Take(quantity - 1).Select(r => r.room_id));

                            foreach (string selectedId in selectedIds)
                            {
                                database.Booking_Details.Add(new Booking_Details
                                {
                                    Booking = booking,
                                    room_id = selectedId,
                                    don_gia = rate
                                });
                            }

                            database.SaveChanges();

                            database.Database.ExecuteSqlCommand(@"
                                INSERT dbo.Booking_Options(
                                    booking_id,services,service_total,
                                    discount_code,discount_percent,discount_amount
                                )
                                VALUES (@p0,@p1,@p2,@p3,@p4,@p5)",
                                booking.booking_id,
                                string.Join(",", serviceKeys),
                                serviceTotal,
                                discount == null ? (object)DBNull.Value : discount.Code,
                                percent,
                                discountAmount);

                            tx.Commit();

                            MyBookingsController.GrantAccess(
                                HttpContext, booking.booking_id);

                            return RedirectToAction(
                                "Index", "ResidentServices",
                                new { id = booking.booking_id });
                        }
                    }
                    catch (System.Data.Entity.Infrastructure.DbUpdateException)
                    {
                        ModelState.AddModelError("",
                            "Chưa lưu được đơn. Vui lòng tải lại và kiểm tra phòng trống.");
                    }
                    catch (System.Data.SqlClient.SqlException)
                    {
                        ModelState.AddModelError("",
                            "Chưa lưu được đơn. Vui lòng tải lại và kiểm tra phòng trống.");
                    }
                    catch (System.Data.Entity.Core.EntityException)
                    {
                        ModelState.AddModelError("",
                            "Chưa lưu được đơn. Vui lòng tải lại và kiểm tra phòng trống.");
                    }
                }
            }

            LoadReserveData(room, start, end);
            ViewBag.SelectedServices = serviceKeys;
            ViewBag.CouponCode = coupon_code;
            return View("Reserve", room);
        }

        public ActionResult Details(int? id)
        {
            if (id == null)
                return new HttpStatusCodeResult(
                    System.Net.HttpStatusCode.BadRequest);

            Booking booking = database.Bookings
                .Include(b => b.User)
                .Include(b => b.Booking_Details)
                .FirstOrDefault(b => b.booking_id == id);

            if (booking == null) return HttpNotFound();
            return View(booking);
        }

        [HttpGet]
        public ActionResult Create(
            int? type_id,
            string roomName,
            string price,
            string image,
            int? area,
            int? capacity)
        {
            var roomTypes = database.Room_Types.AsQueryable();

            if (type_id.HasValue)
                roomTypes = roomTypes.Where(t => t.type_id == type_id.Value);

            ViewBag.RoomTypes = roomTypes.ToList();
            ViewBag.AvailableRooms = database.Rooms
                .Include(r => r.Room_Types).ToList();

            ViewBag.CustomRoomName = roomName;
            ViewBag.CustomPrice = price;
            ViewBag.CustomImage = image;
            ViewBag.CustomArea = area;
            ViewBag.CustomCapacity = capacity;
            return View();
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Create(
            Booking booking,
            string ho_ten,
            string so_dien_thoai,
            string email,
            string[] selectedRooms)
        {
            if (ModelState.IsValid)
            {
                var existingUser = database.Users.FirstOrDefault(
                    u => u.so_dien_thoai == so_dien_thoai);

                int customerId;

                if (existingUser != null)
                    customerId = existingUser.user_id;
                else
                {
                    User newUser = new User
                    {
                        ho_ten = ho_ten,
                        so_dien_thoai = so_dien_thoai,
                        email = string.IsNullOrEmpty(email)
                            ? so_dien_thoai + "@gmail.com" : email,
                        mat_khau = "123456",
                        vai_tro = "Khách hàng"
                    };

                    database.Users.Add(newUser);
                    database.SaveChanges();
                    customerId = newUser.user_id;
                }

                booking.user_id = customerId;
                booking.ngay_dat = DateTime.Now;
                database.Bookings.Add(booking);
                database.SaveChanges();

                if (selectedRooms != null && selectedRooms.Length > 0)
                {
                    foreach (var roomId in selectedRooms)
                    {
                        var room = database.Rooms.FirstOrDefault(
                            r => r.room_id == roomId);

                        decimal donGia = 0;

                        if (room != null && room.Room_Types != null
                            && room.Room_Types.gia_tien.HasValue)
                            donGia = room.Room_Types.gia_tien.Value;

                        database.Booking_Details.Add(new Booking_Details
                        {
                            booking_id = booking.booking_id,
                            room_id = roomId,
                            don_gia = donGia
                        });
                    }

                    database.SaveChanges();
                }

                return RedirectToAction("Index");
            }

            ViewBag.RoomList = database.Rooms
                .Include(r => r.Room_Types).ToList();

            return View(booking);
        }

        [HttpGet]
        public ActionResult Edit(int? id)
        {
            if (id == null)
                return new HttpStatusCodeResult(
                    System.Net.HttpStatusCode.BadRequest);

            Booking booking = database.Bookings
                .Include(b => b.Booking_Details)
                .FirstOrDefault(b => b.booking_id == id);

            if (booking == null) return HttpNotFound();

            ViewBag.user_id = new SelectList(
                database.Users, "user_id", "ho_ten", booking.user_id);

            ViewBag.RoomList = database.Rooms
                .Include(r => r.Room_Types).ToList();

            ViewBag.SelectedRoomIds = booking.Booking_Details
                .Select(d => d.room_id).ToList();

            return View(booking);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Edit(Booking booking, string[] selectedRooms)
        {
            if (ModelState.IsValid)
            {
                database.Entry(booking).State = EntityState.Modified;

                var oldDetails = database.Booking_Details
                    .Where(d => d.booking_id == booking.booking_id).ToList();

                foreach (var oldDetail in oldDetails)
                    database.Booking_Details.Remove(oldDetail);

                if (selectedRooms != null && selectedRooms.Length > 0)
                {
                    foreach (var roomId in selectedRooms)
                    {
                        var room = database.Rooms.FirstOrDefault(
                            r => r.room_id == roomId);

                        decimal donGia = 0;

                        if (room != null && room.Room_Types != null
                            && room.Room_Types.gia_tien.HasValue)
                            donGia = room.Room_Types.gia_tien.Value;

                        database.Booking_Details.Add(new Booking_Details
                        {
                            booking_id = booking.booking_id,
                            room_id = roomId,
                            don_gia = donGia
                        });
                    }
                }

                database.SaveChanges();
                return RedirectToAction("Index");
            }

            ViewBag.user_id = new SelectList(
                database.Users, "user_id", "ho_ten", booking.user_id);

            ViewBag.RoomList = database.Rooms
                .Include(r => r.Room_Types).ToList();

            ViewBag.SelectedRoomIds = selectedRooms != null
                ? selectedRooms.ToList() : new List<string>();

            return View(booking);
        }

        [HttpGet]
        public ActionResult Delete(int? id)
        {
            if (id == null)
                return new HttpStatusCodeResult(
                    System.Net.HttpStatusCode.BadRequest);

            Booking booking = database.Bookings
                .Include(b => b.User)
                .Include(b => b.Booking_Details)
                .FirstOrDefault(b => b.booking_id == id);

            if (booking == null) return HttpNotFound();
            return View(booking);
        }

        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
        public ActionResult DeleteConfirmed(int id)
        {
            Booking booking = database.Bookings.Find(id);

            if (booking != null)
            {
                var details = database.Booking_Details
                    .Where(d => d.booking_id == id).ToList();

                foreach (var detail in details)
                    database.Booking_Details.Remove(detail);

                database.Bookings.Remove(booking);
                database.SaveChanges();
            }

            return RedirectToAction("Index");
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) database.Dispose();
            base.Dispose(disposing);
        }
    }
}