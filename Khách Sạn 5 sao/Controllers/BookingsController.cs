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
            // GET: Booking
            public ActionResult Index()
            {
                var booking = database.Bookings.ToList();
                return View(booking);
            }
            // 2. XEM CHI TIẾT (DETAILS)
            // GET: Bookings/Details/5
            public ActionResult Details(int? id)
            {
                if (id == null)
                {
                    return new HttpStatusCodeResult(System.Net.HttpStatusCode.BadRequest);
                }

                // Lấy thông tin đơn hàng kèm thông tin Khách hàng và Chi tiết danh sách phòng
                Booking booking = database.Bookings
                    .Include(b => b.User)
                    .Include(b => b.Booking_Details)
                    .FirstOrDefault(b => b.booking_id == id);

                if (booking == null)
                {
                    return HttpNotFound();
                }
                return View(booking);
            }

            // GET: Bookings/Create
            [HttpGet]
            public ActionResult Create(int? type_id, string roomName, string price, string image, int? area, int? capacity)
            {
                var roomTypes = database.Room_Types.AsQueryable();
                if (type_id.HasValue)
                {
                    roomTypes = roomTypes.Where(t => t.type_id == type_id.Value);
                }

                ViewBag.RoomTypes = roomTypes.ToList();
                ViewBag.AvailableRooms = database.Rooms.Include(r => r.Room_Types).ToList();

                // Lưu thông tin phòng cụ thể truyền từ DanhSachPhong sang
                ViewBag.CustomRoomName = roomName;
                ViewBag.CustomPrice = price;
                ViewBag.CustomImage = image;
                ViewBag.CustomArea = area;
                ViewBag.CustomCapacity = capacity;

                return View();
            }

            // POST: Bookings/Create
            [HttpPost]
            [ValidateAntiForgeryToken]
            public ActionResult Create(Booking booking, string ho_ten, string so_dien_thoai, string email, string[] selectedRooms)
            {
                if (ModelState.IsValid)
                {
                    // 1. Tự động tìm hoặc tạo mới Khách hàng
                    var existingUser = database.Users.FirstOrDefault(u => u.so_dien_thoai == so_dien_thoai);
                    int customerId;

                    if (existingUser != null)
                    {
                        customerId = existingUser.user_id;
                    }
                    else
                    {
                        User newUser = new User
                        {
                            ho_ten = ho_ten,
                            so_dien_thoai = so_dien_thoai,
                            email = string.IsNullOrEmpty(email) ? (so_dien_thoai + "@gmail.com") : email,
                            mat_khau = "123456",
                            vai_tro = "Khách hàng"
                        };
                        database.Users.Add(newUser);
                        database.SaveChanges();
                        customerId = newUser.user_id;
                    }

                    // 2. Lưu thông tin Đơn đặt phòng (Bookings)
                    booking.user_id = customerId;
                    booking.ngay_dat = DateTime.Now;
                    database.Bookings.Add(booking);
                    database.SaveChanges(); // Lưu để sinh booking_id

                    // 3. Lưu Chi tiết phòng chọn (Booking_Details)
                    if (selectedRooms != null && selectedRooms.Length > 0)
                    {
                        foreach (var roomId in selectedRooms)
                        {
                            var room = database.Rooms.FirstOrDefault(r => r.room_id == roomId);
                            decimal donGia = 0;
                            if (room != null && room.Room_Types != null && room.Room_Types.gia_tien.HasValue)
                            {
                                donGia = room.Room_Types.gia_tien.Value;
                            }

                            Booking_Details detail = new Booking_Details
                            {
                                booking_id = booking.booking_id,
                                room_id = roomId,
                                don_gia = donGia
                            };
                            database.Booking_Details.Add(detail);
                        }
                        database.SaveChanges();
                    }

                    return RedirectToAction("Index");
                }

                ViewBag.RoomList = database.Rooms.Include(r => r.Room_Types).ToList();
                return View(booking);
            }


            // GET: Bookings/Edit/5
            [HttpGet]
            public ActionResult Edit(int? id)
            {
                if (id == null)
                {
                    return new HttpStatusCodeResult(System.Net.HttpStatusCode.BadRequest);
                }

                // Lấy đơn đặt phòng kèm danh sách chi tiết các phòng đã chọn
                Booking booking = database.Bookings
                    .Include(b => b.Booking_Details)
                    .FirstOrDefault(b => b.booking_id == id);

                if (booking == null)
                {
                    return HttpNotFound();
                }

                // Nạp danh sách Khách hàng
                ViewBag.user_id = new SelectList(database.Users, "user_id", "ho_ten", booking.user_id);

                // Nạp danh sách tất cả các Phòng trong CSDL
                ViewBag.RoomList = database.Rooms.Include(r => r.Room_Types).ToList();

                // Lấy danh sách ID các phòng đã được tick chọn trước đó trong đơn này
                ViewBag.SelectedRoomIds = booking.Booking_Details.Select(d => d.room_id).ToList();

                return View(booking);
            }

            // POST: Bookings/Edit/5
            [HttpPost]
            [ValidateAntiForgeryToken]
            public ActionResult Edit(Booking booking, string[] selectedRooms)
            {
                if (ModelState.IsValid)
                {
                    // 1. Cập nhật thông tin chung của Đơn đặt phòng
                    database.Entry(booking).State = EntityState.Modified;

                    // 2. Xóa toàn bộ chi tiết phòng cũ của đơn này
                    var oldDetails = database.Booking_Details.Where(d => d.booking_id == booking.booking_id).ToList();
                    foreach (var oldDetail in oldDetails)
                    {
                        database.Booking_Details.Remove(oldDetail);
                    }

                    // 3. Thêm lại các chi tiết phòng mới được chọn
                    if (selectedRooms != null && selectedRooms.Length > 0)
                    {
                        foreach (var roomId in selectedRooms)
                        {
                            var room = database.Rooms.FirstOrDefault(r => r.room_id == roomId);
                            decimal donGia = 0;
                            if (room != null && room.Room_Types != null && room.Room_Types.gia_tien.HasValue)
                            {
                                donGia = room.Room_Types.gia_tien.Value;
                            }

                            Booking_Details detail = new Booking_Details
                            {
                                booking_id = booking.booking_id,
                                room_id = roomId,
                                don_gia = donGia
                            };
                            database.Booking_Details.Add(detail);
                        }
                    }

                    database.SaveChanges();
                    return RedirectToAction("Index");
                }

                ViewBag.user_id = new SelectList(database.Users, "user_id", "ho_ten", booking.user_id);
                ViewBag.RoomList = database.Rooms.Include(r => r.Room_Types).ToList();
                ViewBag.SelectedRoomIds = selectedRooms != null ? selectedRooms.ToList() : new List<string>();
                return View(booking);
            }

            // 5. XÓA (DELETE) - XÁC NHẬN XÓA
            [HttpGet]
            public ActionResult Delete(int? id)
            {
                if (id == null)
                {
                    return new HttpStatusCodeResult(System.Net.HttpStatusCode.BadRequest);
                }

                // Lấy thông tin đơn hàng kèm Khách hàng và Danh sách phòng đã chọn
                Booking booking = database.Bookings
                    .Include(b => b.User)
                    .Include(b => b.Booking_Details)
                    .FirstOrDefault(b => b.booking_id == id);

                if (booking == null)
                {
                    return HttpNotFound();
                }

                return View(booking);
            }

            // 2. HÀM THỰC HIỆN XÓA VÀO DATABASE (HTTP POST - Khi bấm nút "Xác Nhận Xóa")
            [HttpPost, ActionName("Delete")]
            [ValidateAntiForgeryToken]
            public ActionResult DeleteConfirmed(int id)
            {
                Booking booking = database.Bookings.Find(id);

                if (booking != null)
                {
                    // 1. Xóa các dòng phòng con trong Booking_Details trước (xử lý khóa ngoại)
                    var details = database.Booking_Details.Where(d => d.booking_id == id).ToList();
                    foreach (var detail in details)
                    {
                        database.Booking_Details.Remove(detail);
                    }

                    // 2. Xóa đơn đặt phòng chính trong bảng Bookings
                    database.Bookings.Remove(booking);

                    // 3. Lưu thay đổi vào CSDL
                    database.SaveChanges();
                }

                return RedirectToAction("Index");
            }

            protected override void Dispose(bool disposing)
            {
                if (disposing)
                {
                    database.Dispose();
                }
                base.Dispose(disposing);
            }

        }
    }