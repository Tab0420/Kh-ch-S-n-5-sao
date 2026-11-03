using Khách_Sạn_5_sao.Models;
using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Mvc;

namespace Khách_Sạn_5_sao.Controllers
{
    public class ResidentServicesController : Controller
    {
        private readonly booking_dbEntities db = new booking_dbEntities();

        public const string CatalogSql = @"
            SELECT s.service_id AS Id,s.service_code AS Code,s.service_name AS Name,
                s.description AS Description,s.image_url AS ImageUrl,s.unit_price AS WalkInPrice,
                dbo.ResidentServicePrice(s.service_id) AS Price,i.duration_minutes AS Duration,
                CONVERT(BIT,CASE WHEN EXISTS(
                    SELECT 1 FROM dbo.Dining_Combos c
                    WHERE c.service_id=s.service_id
                ) THEN 1 ELSE 0 END) AS IsCombo
            FROM dbo.Dining_Services s
            JOIN dbo.Dining_ServiceInventory i ON i.service_id=s.service_id
            WHERE s.service_group='WELLNESS' AND s.enabled=1 AND i.enabled=1
                AND s.pricing_mode='PER_PERSON'
                AND dbo.ResidentServicePrice(s.service_id) IS NOT NULL
            ORDER BY s.service_id";

        public class ServiceRow
        {
            public int Id { get; set; }
            public string Code { get; set; }
            public string Name { get; set; }
            public string Description { get; set; }
            public string ImageUrl { get; set; }
            public decimal WalkInPrice { get; set; }
            public decimal Price { get; set; }
            public int Duration { get; set; }
            public bool IsCombo { get; set; }
        }

        public class RoomRow
        {
            public int Id { get; set; }
            public string Name { get; set; }
            public string Phone { get; set; }
            public DateTime CheckIn { get; set; }
            public DateTime CheckOut { get; set; }
            public int Guests { get; set; }
            public string Status { get; set; }
            public bool Eligible { get; set; }
        }

        public class OrderRow
        {
            public string Code { get; set; }
            public string Name { get; set; }
            public DateTime VisitAt { get; set; }
            public int Guests { get; set; }
            public decimal Price { get; set; }
            public decimal Total { get; set; }
            public string Status { get; set; }
            public string PaymentStatus { get; set; }
            public string Itinerary { get; set; }
        }

        public class Form
        {
            public int Id { get; set; }
            public int? ServiceId { get; set; }
            public DateTime? Date { get; set; }
            public int? SlotId { get; set; }
            public int Guests { get; set; } = 1;
            public int Percent { get; set; } = 30;
            public string Token { get; set; }
            public bool Agree { get; set; }
        }

        public class Page
        {
            public int? LookupId { get; set; }
            public RoomRow Room { get; set; }
            public Form Input { get; set; }
            public List<ServiceRow> Services { get; set; } = new List<ServiceRow>();
            public List<OrderRow> Orders { get; set; } = new List<OrderRow>();
        }

        private static DateTime Now
        {
            get { return DateTime.UtcNow.AddHours(7); }
        }

        private bool HasAccess(int id)
        {
            object until = Session["booking-access:" + id];
            return until is DateTime && (DateTime)until > DateTime.UtcNow;
        }

        private static string Phone(string value)
        {
            string s = Regex.Replace(value ?? "", @"[^0-9]", "");
            return s.Length == 11 && s.StartsWith("84")
                ? "0" + s.Substring(2) : s;
        }

        protected override void OnActionExecuting(ActionExecutingContext c)
        {
            Response.Cache.SetCacheability(HttpCacheability.NoCache);
            Response.Cache.SetNoStore();
            base.OnActionExecuting(c);
        }

        private RoomRow Room(int id)
        {
            return db.Database.SqlQuery<RoomRow>(@"
                SELECT b.booking_id AS Id,u.ho_ten AS Name,u.so_dien_thoai AS Phone,
                    DATEADD(HOUR,14,CONVERT(DATETIME2,b.ngay_checkin)) AS CheckIn,
                    DATEADD(HOUR,12,CONVERT(DATETIME2,b.ngay_checkout)) AS CheckOut,
                    COALESCE(b.so_nguoi_lon,1)+COALESCE(b.so_tre_em,0) AS Guests,
                    b.trang_thai AS Status,
                    dbo.ResidentBookingEligible(b.booking_id) AS Eligible
                FROM dbo.Bookings b
                JOIN dbo.Users u ON u.user_id=b.user_id
                WHERE b.booking_id=@p0
                  AND b.ngay_checkin IS NOT NULL
                  AND b.ngay_checkout>b.ngay_checkin",
                id).SingleOrDefault();
        }

        private ActionResult Show(int id, Form input = null)
        {
            var room = Room(id);
            if (room == null) return HttpNotFound();

            var page = new Page
            {
                Room = room,
                Input = input ?? new Form
                {
                    Id = id,
                    Date = room.CheckIn.Date > Now.Date
                        ? room.CheckIn.Date : Now.Date
                }
            };

            if (!page.Input.Date.HasValue)
                page.Input.Date = room.CheckIn.Date > Now.Date
                    ? room.CheckIn.Date : Now.Date;

            string key = "ResidentForm:" + id + ":" + page.Input.Token;
            object until = Session[key];

            if (!(until is DateTime) || (DateTime)until <= DateTime.UtcNow)
            {
                page.Input.Token = Guid.NewGuid().ToString("N");
                Session["ResidentForm:" + id + ":" + page.Input.Token]
                    = DateTime.UtcNow.AddMinutes(30);
            }

            page.Services = db.Database.SqlQuery<ServiceRow>(CatalogSql).ToList();

            page.Orders = db.Database.SqlQuery<OrderRow>(@"
                SELECT r.public_code AS Code,r.service_name AS Name,
                    r.visit_at AS VisitAt,r.guests AS Guests,
                    r.unit_price AS Price,r.estimated_total AS Total,
                    r.status AS Status,
                    COALESCE(p.payment_status,'INCLUDED') AS PaymentStatus,
                    COALESCE(p.staff_note,r.staff_note) AS Itinerary
                FROM dbo.Dining_ResidentReservations l
                JOIN dbo.Dining_Reservations r
                    ON r.reservation_id=l.reservation_id
                LEFT JOIN dbo.Dining_ServicePayments p
                    ON p.reservation_id=r.reservation_id
                WHERE l.booking_id=@p0
                ORDER BY r.created_at_utc DESC",
                id).ToList();

            Session["ResidentBookingId"] = id;
            return View("Index", page);
        }

        [HttpGet]
        public ActionResult Index(int? id)
        {
            if (!id.HasValue && Session["ResidentBookingId"] is int)
                id = (int)Session["ResidentBookingId"];

            if (!id.HasValue || !HasAccess(id.Value))
                return View(new Page { LookupId = id });

            return Show(id.Value);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public ActionResult Access(int? id, string phone)
        {
            var room = id.HasValue && id.Value > 0 ? Room(id.Value) : null;

            if (room == null
                || !Regex.IsMatch(Phone(phone), @"^0[35789][0-9]{8}$")
                || Phone(room.Phone) != Phone(phone))
            {
                ModelState.AddModelError("",
                    "Không tìm thấy đơn phòng khớp mã đơn và số điện thoại.");
                return View("Index", new Page { LookupId = id });
            }

            MyBookingsController.GrantAccess(HttpContext, room.Id);
            return RedirectToAction("Index", new { id = room.Id });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public ActionResult Book(
            [Bind(Include = "Id,ServiceId,Date,SlotId,Guests,Percent,Token,Agree")]
            Form input)
        {
            if (!HasAccess(input.Id))
                return new HttpStatusCodeResult(403);

            string done = Session[
                "ResidentDone:" + input.Id + ":" + input.Token] as string;

            if (!string.IsNullOrEmpty(done))
                return Open(input.Id, done);

            Guid token;
            object until = Session[
                "ResidentForm:" + input.Id + ":" + input.Token];

            if (!Guid.TryParseExact(input.Token ?? "", "N", out token)
                || !(until is DateTime)
                || (DateTime)until <= DateTime.UtcNow)
                ModelState.AddModelError("",
                    "Phiên đặt lịch đã hết hạn. Vui lòng kiểm tra và gửi lại.");

            if (!input.ServiceId.HasValue
                || !input.SlotId.HasValue
                || !input.Date.HasValue
                || input.Guests < 1 || input.Guests > 20
                || (input.Percent != 30 && input.Percent != 100)
                || !input.Agree)
                ModelState.AddModelError("",
                    "Chọn đủ dịch vụ, ngày, giờ, số người, hình thức thanh toán và xác nhận thông tin.");

            if (ModelState.IsValid)
            {
                try
                {
                    string code = db.Database.SqlQuery<string>(@"
                        EXEC dbo.CreateResidentServiceHold
                            @booking_id=@p0,@token=@p1,@service_id=@p2,
                            @slot_id=@p3,@visit_date=@p4,@guests=@p5,@percent=@p6",
                        input.Id, token, input.ServiceId.Value,
                        input.SlotId.Value, input.Date.Value.Date,
                        input.Guests, input.Percent).Single();

                    Session["ResidentDone:" + input.Id + ":" + input.Token] = code;
                    Session.Remove("ResidentForm:" + input.Id + ":" + input.Token);

                    TempData["ResidentMessage"] = code.StartsWith("RS-")
                        ? "Đã xác nhận lịch miễn phí theo đơn phòng."
                        : "Đã giữ chỗ 10 phút. Vui lòng thanh toán để xác nhận lịch.";

                    if (!code.StartsWith("RS-"))
                        TempData["DiningMessage"] = TempData["ResidentMessage"];

                    return Open(input.Id, code);
                }
                catch (SqlException ex)
                {
                    ModelState.AddModelError("", ex.Number == 51000
                        ? ex.Message
                        : "Chưa lưu được lịch. Vui lòng thử lại.");
                }
            }

            return Show(input.Id, input);
        }

        [HttpGet]
        public ActionResult Open(int id, string code)
        {
            if (!HasAccess(id))
                return RedirectToAction("Index", new { id });

            code = (code ?? "").Trim().ToUpperInvariant();

            if (!Regex.IsMatch(code, @"^(RS|DV)-[A-F0-9]{16}$"))
                return HttpNotFound();

            int count = db.Database.SqlQuery<int>(@"
                SELECT COUNT(*)
                FROM dbo.Dining_ResidentReservations l
                JOIN dbo.Dining_Reservations r
                    ON r.reservation_id=l.reservation_id
                WHERE l.booking_id=@p0 AND r.public_code=@p1",
                id, code).Single();

            if (count != 1) return HttpNotFound();

            if (code.StartsWith("RS-"))
                return Redirect(
                    Url.Action("Index", new { id }) + "#resident-orders");

            Session["DiningAccess:" + code] = DateTime.UtcNow.AddMinutes(30);

            return RedirectToAction("Payment", "Dining", new { code });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public ActionResult CancelFree(
            int id, string code, string reason, bool confirm = false)
        {
            if (!HasAccess(id))
                return new HttpStatusCodeResult(403);

            if (!confirm)
            {
                TempData["ResidentMessage"]
                    = "Vui lòng đánh dấu xác nhận hủy.";
                return RedirectToAction("Index", new { id });
            }

            try
            {
                db.Database.ExecuteSqlCommand(
                    "EXEC dbo.CancelResidentFreeService @booking_id=@p0,@code=@p1,@reason=@p2",
                    id, code ?? "", reason ?? "");

                TempData["ResidentMessage"] = "Đã hủy lịch miễn phí.";
            }
            catch (SqlException ex)
            {
                TempData["ResidentMessage"] = ex.Number == 51000
                    ? ex.Message
                    : "Chưa hủy được lịch. Vui lòng thử lại.";
            }

            return Redirect(
                Url.Action("Index", new { id }) + "#resident-orders");
        }

        [HttpGet]
        public ActionResult Availability(int id, int serviceId, DateTime? date)
        {
            if (!HasAccess(id))
                return new HttpStatusCodeResult(403);

            var room = Room(id);

            if (room == null || !room.Eligible || !date.HasValue
                || date.Value.Date < room.CheckIn.Date
                || date.Value.Date > room.CheckOut.Date)
                return new HttpStatusCodeResult(400);

            var rows = db.Database.SqlQuery<DiningController.AvailabilityRow>(@"
                SELECT t.slot_id AS Id,
                    CONVERT(VARCHAR(5),t.start_time,108) AS Time,
                    dbo.ServiceRemaining(
                        s.service_id,x.visit_at,i.duration_minutes,0
                    ) AS Remaining
                FROM dbo.Dining_Slots t
                JOIN dbo.Dining_Services s ON s.service_id=t.service_id
                JOIN dbo.Dining_ServiceInventory i ON i.service_id=s.service_id
                CROSS APPLY(
                    SELECT DATEADD(
                        SECOND,
                        DATEDIFF(SECOND,CONVERT(TIME,'00:00'),t.start_time),
                        @p1
                    ) AS visit_at
                )x
                WHERE s.service_id=@p0
                  AND s.enabled=1 AND i.enabled=1 AND t.enabled=1
                  AND dbo.ResidentServicePrice(s.service_id) IS NOT NULL
                  AND x.visit_at>=@p2 AND x.visit_at>=@p3
                  AND DATEADD(MINUTE,i.duration_minutes,x.visit_at)<=@p4
                ORDER BY t.start_time",
                serviceId, date.Value.Date, Now.AddMinutes(30),
                room.CheckIn, room.CheckOut).ToList();

            return Json(rows, JsonRequestBehavior.AllowGet);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) db.Dispose();
            base.Dispose(disposing);
        }
    }
}