using Khách_Sạn_5_sao.Models;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Data.Entity;
using System.Linq;
using System.Web;
using System.Web.Mvc;

namespace Khách_Sạn_5_sao.Controllers
{
    public class MyBookingsController : Controller
    {
        private readonly booking_dbEntities database =
            new booking_dbEntities();

        public class LookupPage
        {
            [Required(ErrorMessage = "Vui lòng nhập mã đơn đặt phòng.")]
            [Range(1, int.MaxValue,
                ErrorMessage = "Mã đơn phải là số lớn hơn 0.")]
            public int? BookingId { get; set; }

            [Required(
                ErrorMessage = "Vui lòng nhập số điện thoại lúc đặt phòng.")]
            [StringLength(32,
                ErrorMessage = "Số điện thoại không hợp lệ.")]
            public string Phone { get; set; }

            public Booking Order { get; set; }
            public List<RoomRow> Rooms { get; set; }
            public OptionsRow Options { get; set; }
            public List<string> Services { get; set; }
            public PaymentInfo Payment { get; set; }
            public bool CanCancel { get; set; }
            public bool ShowCancelConfirmation { get; set; }
            public string CancelExplanation { get; set; }
            public string BankQrUrl { get; set; }
        }

        public class RoomRow
        {
            public string Name { get; set; }
            public string TypeName { get; set; }
            public decimal Rate { get; set; }
        }

        public class OptionsRow
        {
            public string Services { get; set; }
            public decimal ServiceTotal { get; set; }
            public string DiscountCode { get; set; }
            public decimal DiscountPercent { get; set; }
            public decimal DiscountAmount { get; set; }
        }

        public class PaymentInfo
        {
            public string PaymentStatus { get; set; }
            public string PaymentMethod { get; set; }
            public decimal AmountPaid { get; set; }
            public bool IsDemo { get; set; }
            public string CancellationStatus { get; set; }
            public string CancellationReason { get; set; }
            public string ReviewNote { get; set; }
            public string RefundStatus { get; set; }
            public decimal RefundRequested { get; set; }
            public decimal AmountRefunded { get; set; }
            public DateTime CheckInUtc { get; set; }
            public DateTime FreeCancelUntilUtc { get; set; }
            public bool TransferReported { get; set; }
        }

        public static void GrantAccess(HttpContextBase context, int id)
        {
            context.Session["booking-access:" + id] =
                DateTime.UtcNow.AddMinutes(30);
        }

        private bool HasAccess(int id)
        {
            object until = Session["booking-access:" + id];

            return until is DateTime
                && (DateTime)until > DateTime.UtcNow;
        }

        private static bool IsActive(Booking order)
        {
            return new[]
            {
                "Đã xác nhận",
                "Chờ xác nhận",
                "Chờ thanh toán",
                "Chờ xử lý"
            }.Contains(
                order.trang_thai,
                StringComparer.OrdinalIgnoreCase);
        }

        private PaymentInfo ReadPayment(Booking order)
        {
            return database.Database.SqlQuery<PaymentInfo>(
                @"
                SELECT
                    payment_status AS PaymentStatus,
                    payment_method AS PaymentMethod,
                    amount_paid AS AmountPaid,
                    is_demo AS IsDemo,
                    cancellation_status AS CancellationStatus,
                    cancellation_reason AS CancellationReason,
                    review_note AS ReviewNote,
                    refund_status AS RefundStatus,
                    refund_requested_amount AS RefundRequested,
                    amount_refunded AS AmountRefunded,
                    checkin_at_utc AS CheckInUtc,
                    free_cancel_until_utc AS FreeCancelUntilUtc,
                    CAST(
                        CASE WHEN EXISTS(
                            SELECT 1
                            FROM dbo.Booking_Payment_Events e
                            WHERE e.booking_id = p.booking_id
                              AND e.event_type = 'TRANSFER_REPORTED'
                        ) THEN 1 ELSE 0 END
                        AS BIT
                    ) AS TransferReported
                FROM dbo.Booking_Payments p
                WHERE p.booking_id = @p0
                ",
                order.booking_id
            ).SingleOrDefault() ?? new PaymentInfo
            {
                PaymentStatus = "UNPAID",
                CancellationStatus = "NONE",
                RefundStatus = "NONE",

                // 14:00 Việt Nam = 07:00 UTC.
                CheckInUtc =
                    (order.ngay_checkin ?? DateTime.MinValue.AddDays(2))
                    .Date.AddHours(7),

                FreeCancelUntilUtc =
                    (order.ngay_checkin ?? DateTime.MinValue.AddDays(2))
                    .Date.AddHours(7).AddDays(-1)
            };
        }

        private static string NormalizePhone(string value)
        {
            string phone = new string(
                (value ?? "")
                .Where(c => c >= '0' && c <= '9')
                .ToArray());

            if (phone.StartsWith("84") && phone.Length == 11)
                phone = "0" + phone.Substring(2);

            return phone;
        }

        protected override void OnActionExecuting(
            ActionExecutingContext context)
        {
            Response.Cache.SetCacheability(
                HttpCacheability.NoCache);

            Response.Cache.SetNoStore();

            base.OnActionExecuting(context);
        }

        [HttpGet]
        public ActionResult Index(int? BookingId)
        {
            return View(new LookupPage
            {
                BookingId = BookingId
            });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Index(
            [Bind(Include = "BookingId,Phone")] LookupPage model)
        {
            string phone = NormalizePhone(model.Phone);

            if (phone.Length < 9 || phone.Length > 15)
                ModelState.AddModelError(
                    "Phone", "Số điện thoại không hợp lệ.");

            if (!ModelState.IsValid)
                return View(model);

            var order = database.Bookings
                .AsNoTracking()
                .Include(b => b.User)
                .SingleOrDefault(
                    b => b.booking_id == model.BookingId.Value);

            if (order == null
                || order.User == null
                || NormalizePhone(order.User.so_dien_thoai) != phone)
            {
                ModelState.AddModelError(
                    "",
                    "Không tìm thấy đơn khớp với mã đơn và số điện thoại bạn nhập.");

                return View(model);
            }

            GrantAccess(HttpContext, order.booking_id);

            return RedirectToAction(
                "Manage", new { id = order.booking_id });
        }

        [HttpGet]
        public ActionResult Manage(int id)
        {
            if (!HasAccess(id))
                return RedirectToAction(
                    "Index", new { BookingId = id });

            var model = LoadOrder(id);

            if (model == null)
                return HttpNotFound();

            return View("Index", model);
        }

        private LookupPage LoadOrder(int id)
        {
            var order = database.Bookings
                .AsNoTracking()
                .Include(b => b.User)
                .SingleOrDefault(b => b.booking_id == id);

            if (order == null)
                return null;

            var model = new LookupPage
            {
                BookingId = id,
                Phone = order.User == null
                    ? ""
                    : order.User.so_dien_thoai
            };

            model.Rooms = database.Database.SqlQuery<RoomRow>(
                @"
                SELECT
                    COALESCE(
                        NULLIF(LTRIM(RTRIM(r.ten_phong)), N''),
                        N'Phòng nghỉ'
                    ) AS Name,
                    t.ten_loai AS TypeName,
                    ISNULL(d.don_gia, 0) AS Rate
                FROM dbo.Booking_Details d
                JOIN dbo.Rooms r ON r.room_id = d.room_id
                JOIN dbo.Room_Types t ON t.type_id = r.type_id
                WHERE d.booking_id = @p0
                ORDER BY r.type_id, r.ten_phong
                ",
                order.booking_id
            ).ToList();

            model.Options = database.Database.SqlQuery<OptionsRow>(
                @"
                SELECT
                    services AS Services,
                    service_total AS ServiceTotal,
                    discount_code AS DiscountCode,
                    discount_percent AS DiscountPercent,
                    discount_amount AS DiscountAmount
                FROM dbo.Booking_Options
                WHERE booking_id = @p0
                ",
                order.booking_id
            ).SingleOrDefault();

            var labels = new Dictionary<string, string>
            {
                { "airport", "Đưa đón sân bay 2 chiều" },
                { "breakfast", "Buffet sáng đặc biệt" },
                { "spa", "Trọn gói Spa & Massage" },
                { "motorbike", "Thuê xe máy (24h)" }
            };

            model.Services =
                (model.Options == null
                    ? ""
                    : model.Options.Services ?? "")
                .Split(
                    new[] { ',' },
                    StringSplitOptions.RemoveEmptyEntries)
                .Select(x => x.Trim())
                .Distinct()
                .Select(x => labels.ContainsKey(x)
                    ? labels[x]
                    : "Dịch vụ bổ sung")
                .ToList();

            model.Order = order;
            model.Payment = ReadPayment(order);

            if (model.Payment.PaymentStatus == "PENDING"
                && model.Payment.PaymentMethod == "BANK"
                && IsActive(order)
                && model.Payment.CancellationStatus == "NONE")
            {
                model.BankQrUrl =
                    "https://img.vietqr.io/image/970407-2044444444444-compact2.png?amount="
                    + (order.tong_tien ?? 0).ToString(
                        "0",
                        System.Globalization.CultureInfo.InvariantCulture)
                    + "&addInfo=MLH"
                    + order.booking_id
                    + "&accountName=BUI%20TUAN%20ANH";
            }

            model.CanCancel =
                IsActive(order)
                && order.ngay_checkin.HasValue
                && model.Payment.CheckInUtc > DateTime.UtcNow
                && model.Payment.CancellationStatus == "NONE";

            model.CancelExplanation =
                model.Payment.PaymentStatus == "UNPAID"
                ? "Hủy đơn chưa có giao dịch thanh toán được xác nhận: phòng sẽ được mở lại để đặt."
                : DateTime.UtcNow <= model.Payment.FreeCancelUntilUtc
                    ? "Bạn đủ điều kiện hoàn 100% số tiền thực nhận đã được đối soát. Đơn sẽ được hủy; khoản chuyển chưa đối soát cần được kiểm tra trước khi hoàn. Tiền chỉ được báo đã hoàn khi có xác nhận hoàn tiền."
                    : "Đã qua thời hạn hủy miễn phí. Yêu cầu sẽ được gửi để khách sạn xét; đơn và phòng vẫn được giữ trong lúc chờ, chưa cam kết số tiền hoàn.";

            return model;
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult PrepareCancel(int bookingId)
        {
            if (!HasAccess(bookingId))
                return new HttpStatusCodeResult(403);

            var model = LoadOrder(bookingId);

            if (model == null)
                return HttpNotFound();

            model.ShowCancelConfirmation = model.CanCancel;

            return View("Index", model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Cancel(
            int bookingId,
            string reason,
            bool confirm = false)
        {
            if (!HasAccess(bookingId))
                return new HttpStatusCodeResult(403);

            reason = (reason ?? "").Trim();

            if (!confirm
                || reason.Length < 3
                || reason.Length > 500)
            {
                TempData["BookingMessage"] =
                    "Vui lòng xác nhận hủy và nhập lý do từ 3 đến 500 ký tự.";

                return RedirectToAction(
                    "Manage", new { id = bookingId });
            }

            using (var tx = database.Database.BeginTransaction(
                System.Data.IsolationLevel.Serializable))
            {
                database.Database.SqlQuery<int>(
                    @"SELECT booking_id
                      FROM dbo.Bookings WITH (UPDLOCK,HOLDLOCK)
                      WHERE booking_id = @p0",
                    bookingId
                ).SingleOrDefault();

                var order = database.Bookings
                    .AsNoTracking()
                    .SingleOrDefault(b => b.booking_id == bookingId);

                if (order == null)
                    return HttpNotFound();

                var payment = ReadPayment(order);
                DateTime now = DateTime.UtcNow;

                if (order.trang_thai == "Đã hủy"
                    || payment.CancellationStatus != "NONE")
                {
                    TempData["BookingMessage"] =
                        "Đơn đã hủy hoặc đã có yêu cầu hủy. Không tạo yêu cầu trùng.";

                    return RedirectToAction(
                        "Manage", new { id = bookingId });
                }

                if (!IsActive(order)
                    || !order.ngay_checkin.HasValue
                    || now >= payment.CheckInUtc)
                {
                    TempData["BookingMessage"] =
                        "Đơn này không thể tự hủy trên web. Vui lòng liên hệ khách sạn.";

                    return RedirectToAction(
                        "Manage", new { id = bookingId });
                }

                database.Database.ExecuteSqlCommand(
                    @"
                    IF NOT EXISTS (
                        SELECT 1 FROM dbo.Booking_Payments
                        WHERE booking_id = @p0
                    )
                    INSERT dbo.Booking_Payments
                        (booking_id,checkin_at_utc,free_cancel_until_utc)
                    VALUES (@p0,@p1,@p2)
                    ",
                    bookingId,
                    payment.CheckInUtc,
                    payment.FreeCancelUntilUtc
                );

                bool paid = payment.PaymentStatus == "PAID";
                bool hasTransfer =
                    paid || payment.PaymentStatus == "PENDING";

                bool review =
                    hasTransfer && now > payment.FreeCancelUntilUtc;

                database.Database.ExecuteSqlCommand(
                    @"
                    UPDATE dbo.Booking_Payments
                    SET
                        cancellation_status = @p1,
                        cancellation_reason = @p2,
                        cancellation_requested_at_utc = @p3,
                        cancelled_at_utc = @p4,
                        refund_status = @p5,
                        refund_requested_amount = @p6
                    WHERE booking_id = @p0
                    ",
                    bookingId,
                    review ? "REQUESTED" : "CANCELLED",
                    reason,
                    now,
                    review ? (object)DBNull.Value : now,
                    hasTransfer
                        ? (review ? "REVIEW" : "PENDING")
                        : "NONE",
                    paid ? payment.AmountPaid : 0m
                );

                if (!review)
                {
                    database.Database.ExecuteSqlCommand(
                        @"UPDATE dbo.Bookings
                          SET trang_thai = N'Đã hủy'
                          WHERE booking_id = @p0",
                        bookingId);
                }

                AddEvent(
                    bookingId,
                    review ? "CANCEL_REQUESTED" : "CANCELLED",
                    0,
                    payment.IsDemo);

                if (hasTransfer)
                {
                    AddEvent(
                        bookingId,
                        "REFUND_REQUESTED",
                        payment.AmountPaid,
                        payment.IsDemo);
                }

                tx.Commit();

                TempData["BookingMessage"] = review
                    ? "Đã gửi yêu cầu hủy để khách sạn xét. Đơn chưa bị hủy và chưa có giao dịch hoàn tiền."
                    : paid
                        ? "Đã hủy đơn và ghi nhận yêu cầu hoàn 100%. Tiền chưa được hoàn; trạng thái sẽ cập nhật khi có xác nhận."
                        : hasTransfer
                            ? "Đã hủy đơn. Nếu bạn đã chuyển tiền, khách sạn sẽ đối soát khoản nhận và xử lý hoàn theo chính sách."
                            : "Đã hủy đơn. Phòng đã được mở lại để đặt.";
            }

            return RedirectToAction(
                "Manage", new { id = bookingId });
        }

        private void AddEvent(
            int id,
            string type,
            decimal amount,
            bool isDemo)
        {
            database.Database.ExecuteSqlCommand(
                @"
                INSERT dbo.Booking_Payment_Events
                    (booking_id,event_type,amount,reference,is_demo)
                VALUES (@p0,@p1,@p2,@p3,@p4)
                ",
                id,
                type,
                amount,
                Guid.NewGuid().ToString("N"),
                isDemo);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult BankTransfer(int bookingId)
        {
            if (!HasAccess(bookingId))
                return new HttpStatusCodeResult(403);

            using (var tx = database.Database.BeginTransaction(
                System.Data.IsolationLevel.Serializable))
            {
                database.Database.SqlQuery<int>(
                    @"SELECT booking_id
                      FROM dbo.Bookings WITH (UPDLOCK,HOLDLOCK)
                      WHERE booking_id = @p0",
                    bookingId
                ).SingleOrDefault();

                var order = database.Bookings
                    .AsNoTracking()
                    .SingleOrDefault(b => b.booking_id == bookingId);

                if (order == null)
                    return HttpNotFound();

                var payment = ReadPayment(order);

                if (!IsActive(order)
                    || payment.CancellationStatus != "NONE"
                    || payment.CheckInUtc <= DateTime.UtcNow
                    || payment.PaymentStatus == "PAID"
                    || !order.tong_tien.HasValue
                    || order.tong_tien <= 0
                    || decimal.Truncate(order.tong_tien.Value)
                        != order.tong_tien.Value)
                {
                    TempData["BookingMessage"] =
                        "Đơn này không thể tạo yêu cầu chuyển khoản. Vui lòng liên hệ khách sạn.";

                    return RedirectToAction(
                        "Manage", new { id = bookingId });
                }

                database.Database.ExecuteSqlCommand(
                    @"
                    IF NOT EXISTS (
                        SELECT 1 FROM dbo.Booking_Payments
                        WHERE booking_id = @p0
                    )
                    INSERT dbo.Booking_Payments
                        (booking_id,checkin_at_utc,free_cancel_until_utc)
                    VALUES (@p0,@p1,@p2);

                    UPDATE dbo.Booking_Payments
                    SET payment_status = 'PENDING',
                        payment_method = 'BANK'
                    WHERE booking_id = @p0;

                    UPDATE dbo.Bookings
                    SET phuong_thuc_tt = N'Chuyển khoản Techcombank'
                    WHERE booking_id = @p0;
                    ",
                    bookingId,
                    payment.CheckInUtc,
                    payment.FreeCancelUntilUtc
                );

                int count = database.Database.SqlQuery<int>(
                    @"SELECT COUNT(*)
                      FROM dbo.Booking_Payment_Events
                      WHERE booking_id = @p0
                        AND event_type = 'TRANSFER_INITIATED'",
                    bookingId
                ).Single();

                if (count != 1)
                {
                    AddEvent(
                        bookingId,
                        "TRANSFER_INITIATED",
                        order.tong_tien.Value,
                        false);
                }

                tx.Commit();
            }

            return RedirectToAction(
                "Manage", new { id = bookingId });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult ReportTransfer(int bookingId)
        {
            if (!HasAccess(bookingId))
                return new HttpStatusCodeResult(403);

            using (var tx = database.Database.BeginTransaction(
                System.Data.IsolationLevel.Serializable))
            {
                database.Database.SqlQuery<int>(
                    @"SELECT booking_id
                      FROM dbo.Bookings WITH (UPDLOCK,HOLDLOCK)
                      WHERE booking_id = @p0",
                    bookingId
                ).SingleOrDefault();

                var order = database.Bookings
                    .AsNoTracking()
                    .SingleOrDefault(b => b.booking_id == bookingId);

                if (order == null)
                    return HttpNotFound();

                var payment = ReadPayment(order);

                if (!IsActive(order)
                    || payment.CancellationStatus != "NONE"
                    || payment.PaymentStatus != "PENDING"
                    || payment.PaymentMethod != "BANK")
                {
                    return new HttpStatusCodeResult(409);
                }

                if (!payment.TransferReported)
                {
                    AddEvent(
                        bookingId,
                        "TRANSFER_REPORTED",
                        order.tong_tien ?? 0,
                        false);
                }

                tx.Commit();
            }

            TempData["BookingMessage"] =
                "Đã ghi nhận thông báo chuyển khoản. Đơn vẫn chờ đối soát; thông báo này chưa phải xác nhận đã nhận tiền.";

            return RedirectToAction(
                "Manage", new { id = bookingId });
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
                database.Dispose();

            base.Dispose(disposing);
        }
    }

    public class BookingFlowFilter : ActionFilterAttribute
    {
        public override void OnActionExecuting(
            ActionExecutingContext context)
        {
            if (!string.Equals(
                context.RouteData.Values["controller"] as string,
                "Bookings",
                StringComparison.OrdinalIgnoreCase))
                return;

            string action = context.ActionDescriptor.ActionName;

            if (action.Equals(
                "Create", StringComparison.OrdinalIgnoreCase))
            {
                context.Result =
                    context.HttpContext.Request.HttpMethod == "GET"
                    ? (ActionResult)new RedirectToRouteResult(
                        new System.Web.Routing.RouteValueDictionary(
                            new
                            {
                                controller = "Bookings",
                                action = "Index",
                                type_id = context.ActionParameters["type_id"]
                            }))
                    : new HttpStatusCodeResult(
                        403, "Use the reservation flow.");
            }

            if (action.Equals(
                "Details", StringComparison.OrdinalIgnoreCase))
            {
                context.Result = new RedirectToRouteResult(
                    new System.Web.Routing.RouteValueDictionary(
                        new
                        {
                            controller = "MyBookings",
                            action = "Manage",
                            id = context.ActionParameters["id"]
                        }));
            }

            if (action.Equals(
                    "Edit", StringComparison.OrdinalIgnoreCase)
                || action.Equals(
                    "Delete", StringComparison.OrdinalIgnoreCase))
            {
                context.Result = new HttpStatusCodeResult(
                    403, "Use the booking cancellation flow.");
            }
        }

        public override void OnActionExecuted(
            ActionExecutedContext context)
        {
            if (context.Exception != null
                || context.HttpContext.Request.HttpMethod != "POST"
                || !string.Equals(
                    context.RouteData.Values["controller"] as string,
                    "Bookings",
                    StringComparison.OrdinalIgnoreCase)
                || !context.ActionDescriptor.ActionName.Equals(
                    "Reserve", StringComparison.OrdinalIgnoreCase))
                return;

            var redirect =
                context.Result as RedirectToRouteResult;

            int id;

            if (redirect != null
                && string.Equals(
                    redirect.RouteValues["action"] as string,
                    "Details",
                    StringComparison.OrdinalIgnoreCase)
                && int.TryParse(
                    Convert.ToString(redirect.RouteValues["id"]),
                    out id)
                && id > 0)
            {
                MyBookingsController.GrantAccess(
                    context.HttpContext, id);

                context.Result = new RedirectToRouteResult(
                    new System.Web.Routing.RouteValueDictionary(
                        new
                        {
                            controller = "MyBookings",
                            action = "Manage",
                            id = id
                        }));
            }
        }
    }
}